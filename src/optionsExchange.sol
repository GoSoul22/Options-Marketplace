// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./positionNFT.sol";
import "./interfaces/IWETH.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract optionsExchange is ERC721Holder, EIP712("OptionExchange", "1.0"), Ownable {
    using SafeERC20 for IERC20;

    positionNFT public PNFT;
    IWETH public immutable WETH;

    uint256 public makerFee;
    uint256 public takerFee;
    address public feeAddress;


    struct ERC20Asset{
        address token;
        uint256 amount;
    }

    struct ERC721Asset{
        address token;
        uint256 tokenId;
    }

    struct Order{
        address maker;
        bool isCall;
        bool isLong;
        bool isERC20;
        address baseAsset;  // token used to pay premium and strike price
        uint256 strike;     // strike price
        uint256 premium;    // insurance fee
        uint256 duration;   // in seconds
        uint256 expiration; // last day to fill this order 
        uint256 nonce;      // ensure replay attacks are not possible.
        ERC20Asset underlyingERC20;
        ERC721Asset underlyingERC721;
    }

    
    
    mapping(uint256 => bool) public usedNonce; //ensure replay attacks are not possible.
    mapping(uint256 => bool) public OrderCancelled;
    mapping(uint256 => uint256) public exerciseDate;
    mapping(address => bool) public whiteListedBaseAsset;


    bytes32 public constant ERC20ASSET_TYPE_HASH =
        keccak256(abi.encodePacked("ERC20Asset(address token,uint256 amount)"));

    bytes32 public constant ERC721ASSET_TYPE_HASH =
        keccak256(abi.encodePacked("ERC721Asset(address token,uint256 tokenId)"));

    bytes32 public constant ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(
            "Order(address maker,bool isCall,bool isLong,bool isERC20,address baseAsset,uint256 strike,uint256 premium,uint256 duration,uint256 expiration,uint256 nonce,ERC20Asset underlyingERC20,ERC721Asset underlyingERC721)",
            "ERC20Asset(address token,uint256 amount)",
            "ERC721Asset(address token,uint256 tokenId)"
        ));

    event NewMakerFee(uint256 _fee);
    event NewTakerFee(uint256 _fee);
    event NewFeeAddress(address _feeAddress);
    event NewBaseAsset(address _baseAsset, bool _flag);
    event FilledOrder(Order _order);
    event CancelledOrder(Order _order);
    event ExercisedOrder(Order _order);
    event WithdrawnOrder(Order _order);


    constructor(address _WETH, address[] memory _baseAssets) {
        // require(_feeAddress != address(0) , "Invalid fee address.");
        require(_WETH != address(0), "Invalid WETH address.");

        // feeAddress = _feeAddress;
        PNFT = new positionNFT();
        WETH = IWETH(_WETH);
        for(uint256 i = 0; i < _baseAssets.length; i++){
            whiteListedBaseAsset[_baseAssets[i]] = true;
        }
    }

    //** Main Logic */

    function fillOrder(Order memory _order, bytes calldata _signature) external payable returns(uint256, uint256){
        
        //** Checks */
        bytes32 orderHash = getOrderStructHash(_order);  //return a hash of the order based on EIP-712 
        require(!usedNonce[_order.nonce], "Nonce has been used");
        require(_order.maker != msg.sender, "Invalid order taker"); 
        require(_order.strike > 0, "Strike must be greater than 0");
        require(_order.premium > 0, "Premium must be greater than 0");
        require(_order.expiration > block.timestamp, "Order has expired");
        require(!OrderCancelled[uint256(orderHash)], "Order has been cancelled");
        require(_order.duration <= 365 days, "Duration must be less than 365 days");
        require(whiteListedBaseAsset[_order.baseAsset], "Base asset is not whitelisted");
        require(SignatureChecker.isValidSignatureNow(_order.maker, orderHash, _signature), "Invalid signature");
        if(_order.isERC20){
            require(_order.underlyingERC20.amount > 0, "No ERC20 assets to fill");
            require(_order.underlyingERC20.token != address(0), "No ERC20 assets to fill");
            require(_order.underlyingERC721.token == address(0), "ERC721 assets are not supported");
        }else {
            require(_order.underlyingERC721.token != address(0), "No ERC721 assets to fill");
            require(_order.underlyingERC20.amount == 0, "ERC20 assets are not supported");
            require(_order.underlyingERC20.token == address(0), "ERC20 assets are not supported"); 
        }

        //** Effects */
        // mint posiiton NFTs to maker and taker
        bytes32 oppositeOrderHash = getOppositeOrderStructHash(_order);
        PNFT.safeMint(_order.maker, uint256(orderHash));
        PNFT.safeMint(msg.sender, uint256(oppositeOrderHash));

        usedNonce[_order.nonce] = true;
        exerciseDate[_order.isLong ? uint256(orderHash) : uint256(oppositeOrderHash)] = _order.duration + block.timestamp;


        //** Interactions */
        // transfer premium
        if(_order.isLong){
            IERC20(_order.baseAsset).safeTransferFrom(_order.maker, msg.sender, _order.premium);
        }else{
            if(_order.baseAsset == address(WETH) && msg.value > 0){
                //pay with ETH instead of WETH
                require(msg.value == _order.premium, "Premium must be equal to msg.value");
                WETH.deposit{value: msg.value}();
                WETH.transfer(_order.maker, _order.premium);
            }else{
                IERC20(_order.baseAsset).safeTransferFrom(msg.sender, _order.maker, _order.premium);
            }
        }
        
        //transfer strike(ERC20/ERC721) assets
        //cannot be optimized but left for readability
        if(_order.isLong && _order.isCall){
            // long call
            //transfer the strike(ERC20/ERC721) from msg.sender to contract
            if (_order.isERC20){
                IERC20(_order.underlyingERC20.token).safeTransferFrom(msg.sender, address(this), _order.underlyingERC20.amount);
            }else{
                IERC721(_order.underlyingERC721.token).safeTransferFrom(msg.sender, address(this), _order.underlyingERC721.tokenId);
            }
        }else if (_order.isLong && !_order.isCall){
            // long put
            //transfer the strike(ETH/ERC20) from msg.sender to contract
            if(_order.baseAsset == address(WETH) && msg.value > 0){
                require(msg.value == _order.strike, "Strike must be equal to msg.value");
                WETH.deposit{value: msg.value}();
            }else{
                IERC20(_order.baseAsset).safeTransferFrom(msg.sender, address(this), _order.strike);
            }
        }else if (!_order.isLong && _order.isCall){
            // short call
             //transfer the strike(ERC20/ERC721) from  _order.maker to contract    
            if (_order.isERC20){
                IERC20(_order.underlyingERC20.token).safeTransferFrom(_order.maker, address(this), _order.underlyingERC20.amount);
            }else{
                IERC721(_order.underlyingERC721.token).safeTransferFrom(_order.maker, address(this), _order.underlyingERC721.tokenId);
            } 
        }else if (!_order.isLong && !_order.isCall){
            // short put
            //transfer the strike(ERC20) from msg.sender to contract
            IERC20(_order.baseAsset).safeTransferFrom(_order.maker, address(this), _order.strike);
        }

        emit FilledOrder(_order);

        return (uint256(orderHash), uint256(oppositeOrderHash));
    }

    // exercise a long position and burn long position NFT
    function exerciseOrder(Order memory _order) external payable {
        
        //** Checks */
        bytes32 orderHash = getOrderStructHash(_order);
        require(_order.isLong, "Only long position can be exercised");
        require(exerciseDate[uint(orderHash)] >= block.timestamp, "Order has expired");
        require(PNFT.ownerOf(uint256(orderHash)) == msg.sender, "Only long position owner can exercise or order has been exercised");

         //** Effects */
        //Checks Effects Interactions pattern: burn long position NFT 
        PNFT.burn(uint256(orderHash));

         //** Interactions */
        if(_order.isCall){
            //long call
            //If the price raises above the strike price,  msg.sender has the right to buy the underlying at the strike price.
            //to buy the underlying at the strike price, msg.sender needs to transfer the strike(ERC20/ERC721) to contract.
            //pay with eth/erc20
            if (_order.baseAsset == address(WETH) && msg.value > 0){
                require(msg.value == _order.strike, "Strike must be equal to msg.value");
                WETH.deposit{value: msg.value}();
            }else{
                IERC20(_order.baseAsset).safeTransferFrom(msg.sender, address(this), _order.strike);
            }
            //transfer the underlying(ERC20/ERC721) from contract to order maker(msg.sender)
            if (_order.isERC20){
                IERC20(_order.underlyingERC20.token).safeTransfer(msg.sender, _order.underlyingERC20.amount);
            }else{
                IERC721(_order.underlyingERC721.token).safeTransferFrom(address(this), msg.sender, _order.underlyingERC721.tokenId);
            }
        }else{
            //long put
            //If the price falls below the strike price, msg.sender has the right to sell the underlying(ERC20/ERC721) at the strike price. 
            // to sell the underlying(ERC20/ERC721) at the strike price, msg.sender needs to transfer the underlying(ERC20/ERC721) to contract.
            if(_order.isERC20){
                IERC20(_order.underlyingERC20.token).safeTransferFrom(msg.sender, address(this), _order.underlyingERC20.amount);
            }else{
                IERC721(_order.underlyingERC721.token).safeTransferFrom(msg.sender, address(this), _order.underlyingERC721.tokenId);
            }

            //transfer the strike(ETH/ERC20) from contract to msg.sender.
            IERC20(_order.baseAsset).safeTransfer(msg.sender, _order.strike);
        }


        emit ExercisedOrder(_order);
    }

    // withdraw a short position and burn short position NFT
    function withdrawOrder(Order memory _order) external{

        //** Checks */
        bytes32 orderHash = getOrderStructHash(_order);
        bytes32 longOrderHash = getOppositeOrderStructHash(_order);
        bool isExercised = !PNFT.exists(uint256(longOrderHash));
        require(!_order.isLong, "Only short position can be withdrawn");
        require(PNFT.ownerOf(uint256(orderHash)) == msg.sender, "Only short position owner can withdraw or order has been withdrawn");
        require(exerciseDate[uint256(longOrderHash)] < block.timestamp || isExercised, "Order has not expired or long position has not been exercised");

         //** Effects */
        //burn short position NFT
        PNFT.burn(uint256(orderHash));

         //** Interactions */
        if(_order.isCall && isExercised){
            // short Call exercised 
            //     1. order maker receives a premium for writing an option from msg.sender. -> transfer premium from msg.sender(is long) to order maker(is short)
            //     2. order maker is obligated to sell the underlying at the strike price to the option owner. -> transfer the underlying(ERC20/721) from order maker to contract
            //     3. order maker can withdraw the strike(WETH/DAI/USDT/BUSD/USDC)
            IERC20(_order.baseAsset).safeTransfer(msg.sender, _order.strike);
        }else if (_order.isCall && !isExercised){
            // Short Call not exercised
            //  3. order maker can withdraw the underlying(ERC20/ERC721)
            if (_order.isERC20){
                IERC20(_order.underlyingERC20.token).safeTransfer(msg.sender, _order.underlyingERC20.amount);
            }else{
                IERC721(_order.underlyingERC721.token).safeTransferFrom(address(this), msg.sender, _order.underlyingERC721.tokenId);
            }
        }else if (!_order.isCall && isExercised){
            // Short Put exercised
            // 1. order maker receives a premium for writing an option from msg.sender(taker). -> transfer premium from msg.sender(is long) to order maker(is short)
            // 2. order maker is obligated to buy the underlying at the strike price from the option owner.   -> transfer strike(WETH/DAI) from order maker to contract
            // 3. order maker can withdraw the underlying(ERC20/ERC721)
            if (_order.isERC20){
                IERC20(_order.underlyingERC20.token).safeTransfer(msg.sender, _order.underlyingERC20.amount);
            }else{
                IERC721(_order.underlyingERC721.token).safeTransferFrom(address(this), msg.sender, _order.underlyingERC721.tokenId);
            }  
        }else{
            // Short Put not exercised
             // 3. order maker can withdraw the strike(WETH/DAI)
            IERC20(_order.baseAsset).safeTransfer(msg.sender, _order.strike);
        }
    

        emit WithdrawnOrder(_order);
    }

    //cancel an offchain order that user no longer want to be filled.
    function cancelOrder(Order memory _order) external {
        require(_order.maker == msg.sender, "Not your order");
        bytes32 orderHash = getOrderStructHash(_order);
        require(!PNFT.exists(uint256(orderHash)), "Order has been filled");

        OrderCancelled[uint256(orderHash)] = true;

        emit CancelledOrder(_order);
    }

    //** internal function */
    function getOrderStructHash(Order memory _order) public returns (bytes32) {
        bytes32 orderHash = keccak256(abi.encode(
            ORDER_TYPE_HASH,
            _order.maker,
            _order.isCall,
            _order.isLong,
            _order.isERC20,
            _order.baseAsset,
            _order.strike,
            _order.premium,
            _order.duration,
            _order.expiration,
            _order.nonce,
            getERC20AssetHash(_order.underlyingERC20),
            getERC721AssetHash(_order.underlyingERC721)
        ));

        return _hashTypedDataV4(orderHash);
    }


    function getERC20AssetHash(ERC20Asset memory _asset) internal returns (bytes32 assetHash){
        return keccak256(abi.encode(ERC20ASSET_TYPE_HASH, _asset.token, _asset.amount));
    }

    function getERC721AssetHash(ERC721Asset memory _asset) internal returns (bytes32 assetHash){
        return keccak256(abi.encode(ERC721ASSET_TYPE_HASH, _asset.token, _asset.tokenId));
    }

    function getOppositeOrderStructHash(Order memory _order) internal returns (bytes32) {
        Order memory oppositePosition = abi.decode(abi.encode(_order), (Order));

        oppositePosition.isLong = !_order.isLong;
        bytes32 orderHash = getOrderStructHash(oppositePosition);
        return orderHash;
    }

    //** OnlyOwner functions */
    function setFees(uint256 _fee, bool isMaker) external onlyOwner {
        require(_fee < 10, "Fee must be less than 10");

        if (isMaker){
            makerFee = _fee;
            emit NewMakerFee(_fee);
        } else {
            takerFee = _fee;
            emit NewTakerFee(_fee);
        }
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "Invalid fee address.");
        feeAddress = _feeAddress;

        emit NewFeeAddress(_feeAddress);
    }

    function setBaseAsset(address _baseAsset, bool _flag) external onlyOwner {
        whiteListedBaseAsset[_baseAsset] =  _flag;
 
        emit NewBaseAsset(_baseAsset, _flag);
    }

    function isNonceUsed(uint256 _nonce) external view returns (bool) {
        return usedNonce[_nonce];
    }


}

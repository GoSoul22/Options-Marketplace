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
        address baseAsset;  //underlying asset
        uint256 strike;     // strike price * amount of baseAsset
        uint256 premium;    // insurance fee
        uint256 duration;
        uint256 expiration; // last day to fill this order 
        uint256 nonce;      // make sure every order hash is different
        address[] whitelist;
        ERC20Asset[] ERC20Assets;
        ERC721Asset[] ERC721Assets;
    }

    mapping(uint256 => uint256) public exerciseDate;
    mapping(address => bool) public whiteListedBaseAsset;
    mapping(uint256 => bool) public OrderCancelled;
    mapping(uint256 => bool) public usedNonce; //ensure replay attacks are not possible.


    bytes32 public constant ERC20ASSET_TYPE_HASH =
        keccak256(abi.encodePacked("ERC20Asset(address token,uint256 amount)"));

    bytes32 public constant ERC721ASSET_TYPE_HASH =
        keccak256(abi.encodePacked("ERC721Asset(address token,uint256 tokenId)"));

    bytes32 public constant ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(
            "Order(address maker,bool isCall,bool isLong,address baseAsset,uint256 strike,uint256 premium,uint256 duration,uint256 expiration,uint256 nonce,address[] whitelist,ERC20Asset[] ERC20Assets,ERC721Asset[] ERC721Assets)",
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

    function fillOrder(Order memory _order, bytes calldata _signature) external payable returns(uint256){

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
        require(_order.whitelist.length == 0 || isWhiteListed(msg.sender, _order.whitelist), "User is not whitelisted");


        // mint posiiton NFTs to maker and taker
        bytes32 oppositeOrderHash = getOppositeOrderStructHash(_order);
        PNFT.safeMint(_order.maker, uint256(orderHash));
        PNFT.safeMint(msg.sender, uint256(oppositeOrderHash));

        exerciseDate[_order.isLong ? uint256(orderHash) : uint256(oppositeOrderHash)] = _order.duration + block.timestamp;


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
        if(_order.isLong && _order.isCall){
            // long call
            //transfer the strike(ERC20/ERC721) from msg.sender to contract
            transferERC20In(_order.ERC20Assets, msg.sender);
            transferERC721In(_order.ERC721Assets, msg.sender);
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
            transferERC20In(_order.ERC20Assets, _order.maker);
            transferERC721In(_order.ERC721Assets, _order.maker);            
        }else if (!_order.isLong && !_order.isCall){
            // short put
            //transfer the strike(ERC20) from msg.sender to contract
            IERC20(_order.baseAsset).safeTransferFrom(_order.maker, address(this), _order.strike);
        }

        emit FilledOrder(_order);

        return uint256(oppositeOrderHash);
    }

    // exercise a long position and burn long position NFT
    function exerciseOrder(Order memory _order) external payable {
        
        bytes32 orderHash = getOrderStructHash(_order);
        require(_order.isLong, "Only long position can be exercised");
        require(exerciseDate[uint(orderHash)] >= block.timestamp, "Order has expired");
        require(PNFT.ownerOf(uint256(orderHash)) == msg.sender, "Only long position owner can exercise or order has been exercised");


        //burn long position NFT
        PNFT.burn(uint256(orderHash));

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
            //transfer the underlying(ERC20/ERC721) from contract to order maker
            transferERC20Out(_order.ERC20Assets, msg.sender);
            transferERC721Out(_order.ERC721Assets, msg.sender);
        }else{
            //long put
            //If the price falls below the strike price, order maker has the right to sell the underlying(ERC20/ERC721) at the strike price. 
            //-> transfer strike(ETH/ERC20) from msg.senfer(taker) to contract  
            // to sell the underlying(ERC20/ERC721) at the strike price, msg.sender needs to transfer the underlying(ERC20/ERC721) to contract.
            transferERC20In(_order.ERC20Assets, msg.sender);
            transferERC721In(_order.ERC721Assets, msg.sender);

            //transfer the strike(ETH/ERC20) from contract to msg.sender.
            IERC20(_order.baseAsset).safeTransfer(msg.sender, _order.strike);
        }


        emit ExercisedOrder(_order);
    }

    // withdraw a short position and burn short position NFT
    function withdrawOrder(Order memory _order) external{

        bytes32 orderHash = getOrderStructHash(_order);
        bytes32 oppositeOrderHash = getOppositeOrderStructHash(_order);
        bool isExercised = PNFT.ownerOf(uint(oppositeOrderHash)) == address(0) ? true : false;
        
        require(!_order.isLong, "Only short position can be withdrawn");
        require(PNFT.ownerOf(uint(orderHash)) == msg.sender, "Only short position owner can withdraw or order has been withdrawn");
        require(exerciseDate[uint(orderHash)] < block.timestamp || isExercised, "Order has not expired or long position has not been exercised");

        
        //burn short position NFT
        PNFT.burn(uint256(orderHash));


        if(_order.isCall && isExercised){
            // short Call exercised 
            //     1. order maker receives a premium for writing an option from msg.sender. -> transfer premium from msg.sender(is long) to order maker(is short)
            //     2. order maker is obligated to sell the underlying at the strike price to the option owner. -> transfer the underlying(ERC20/721) from order maker to contract
            //     3. order maker can withdraw the strike(WETH/DAI/USDT/BUSD/USDC)
            IERC20(_order.baseAsset).safeTransfer(msg.sender, _order.strike);
        }else if (_order.isCall && !isExercised){
            // Short Call not exercised
            //  3. order maker can withdraw the underlying(ERC20/ERC721)
            transferERC20Out(_order.ERC20Assets, msg.sender);
            transferERC721Out(_order.ERC721Assets, msg.sender);
        }else if (!_order.isCall && isExercised){
            // Short Put exercised
            // 1. order maker receives a premium for writing an option from msg.sender(taker). -> transfer premium from msg.sender(is long) to order maker(is short)
            // 2. order maker is obligated to buy the underlying at the strike price from the option owner.   -> transfer strike(WETH/DAI) from order maker to contract
            // 3. order maker can withdraw the underlying(ERC20/ERC721)
            transferERC20Out(_order.ERC20Assets, msg.sender);
            transferERC721Out(_order.ERC721Assets, msg.sender);   
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
        require(PNFT.ownerOf(uint256(orderHash)) == address(0), "Order has been filled");

        OrderCancelled[uint256(orderHash)] = true;

        emit CancelledOrder(_order);
    }

    //** internal function */

    function transferERC20In(ERC20Asset[] memory assets, address from) internal {
        for(uint256 i = 0; i < assets.length; ++i){
            IERC20(assets[i].token).safeTransferFrom(from, address(this), assets[i].amount);
        }
    }

    function transferERC20Out(ERC20Asset[] memory assets, address to) internal {
        for(uint256 i = 0; i < assets.length; ++i){
            IERC20(assets[i].token).safeTransfer(to, assets[i].amount);
        }
    }

    function transferERC721In(ERC721Asset[] memory assets, address from) internal {
        for(uint256 i = 0; i < assets.length; ++i){
            IERC721(assets[i].token).safeTransferFrom(from, address(this), assets[i].tokenId);
        }
    }

    function transferERC721Out(ERC721Asset[] memory assets, address to) internal {
        for(uint256 i = 0; i < assets.length; ++i){
            IERC721(assets[i].token).safeTransferFrom(address(this), to, assets[i].tokenId);
        }
    }

    function isWhiteListed(address _user, address[] memory _whitelist) internal pure returns (bool){
        for(uint256 i = 0; i < _whitelist.length; ++i){
            if(_user == _whitelist[i]){
                return true;
            }
        }
        return false;
    }

    function getOrderStructHash(Order memory _order) public returns (bytes32) {
        bytes32 orderHash = keccak256(abi.encode(
            ORDER_TYPE_HASH,
            _order.maker,
            _order.isCall,
            _order.isLong,
            _order.baseAsset,
            _order.strike,
            _order.premium,
            _order.duration,
            _order.expiration,
            _order.nonce,
            keccak256(abi.encodePacked(_order.whitelist)),
            keccak256(getERC20AssetsHash(_order.ERC20Assets)),
            keccak256(getERC721AssetsHash(_order.ERC721Assets))
        ));

        return _hashTypedDataV4(orderHash);
    }

    function getERC20AssetsHash(ERC20Asset[] memory assets) internal returns (bytes memory assetHash){
        for(uint256 i = 0; i< assets.length; ++i){
            assetHash = abi.encodePacked(assetHash, keccak256(abi.encode(
                    ERC20ASSET_TYPE_HASH,
                    assets[i].token,
                    assets[i].amount
            )));
        }

        return assetHash;
    }

    function getERC721AssetsHash(ERC721Asset[] memory assets) internal returns (bytes memory assetHash){
        for(uint256 i = 0; i< assets.length; ++i){
            assetHash = abi.encodePacked(assetHash, keccak256(abi.encode(
                    ERC721ASSET_TYPE_HASH,
                    assets[i].token,
                    assets[i].tokenId
            )));
        }

        return assetHash;
    }

    function getOppositeOrderStructHash(Order memory _order) internal returns (bytes32) {
        // _order.isLong = !_order.isLong;

        // return getOrderStructHash(_order);

        Order memory oppositePosition = abi.decode(abi.encode(_order), (Order));

        oppositePosition.isLong = !_order.isLong;
        bytes32 orderHash = getOrderStructHash(oppositePosition);
        return orderHash;
    }

    //** OnlyOner functions */
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

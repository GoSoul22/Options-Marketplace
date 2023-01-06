// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./positionNFT.sol";
// import "./interfaces/IWETH.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

// import "@openzeppelin/contracts/utils/String.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract optionsExchange is ERC721Holder, EIP712("OptionExchange", "1.0"), Ownable {
    using SafeERC20 for IERC20;

    positionNFT public PNFT;
    IERC20 public immutable WETH;

    uint256 public fee;

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
        address baseAsset; //underlying asset
        uint256 strike;     // strike price * amount of baseAsset
        uint256 premium;    // insurance fee
        uint256 duration;
        uint256 expiration;
        uint256 nonce;
        address[] whitelist;
        ERC20Asset[] ERC20Assets;
        ERC721Asset[] ERC721Assets;
    }

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

    event NewFee(uint256 fee);


    constructor(address _WETH){
        PNFT = new positionNFT();
        WETH = IERC20(_WETH);
    }


    function setFee(uint256 _fee) public onlyOwner {
        require(_fee < 100, "Fee must be less than 100");
        fee = _fee;

        emit NewFee(_fee);
    }

     /**
        @notice Fill an offchain order and settels it onchain.  
        @param order The order to be filled.
        @param signature The signature of the order.
        @return orderHash The eip-712 compliant hash of the order.
     */

    function fillOrder(Order _order, bytes calldata _signature) external payable {

        bytes32 orderHash = getOrderStructHash(_order);  //return a hash of the order based on EIP-712
        
        require(_order.expiration < block.timestamp, "Order has expired");
        require(_order.duration <= 365 days, "Duration must be less than 365 days");
        require(_order.premium > 0, "Premium must be greater than 0");
        require(_order.strike > 0, "Strike must be greater than 0");


    }





    /**
        @notice Computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer  
        @param order The order to be hashed.
        @return orderHash The eip-712 compliant hash of the order.
     */
    function getOrderStructHash(Order memory _order) internal pure returns (bytes32) {
        orderHash = keccak256(abi.encode(
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
            keccak256(abi.encodePacked(_order.ERC20Assets)),
            keccak256(abi.encodePacked(_order.ERC721Assets))
        ));

        return _hashTypedDataV4(orderHash);
    }




}

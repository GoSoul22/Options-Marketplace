// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../libraries/dataStructs.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";


contract sigUtils is EIP712("OptionExchange", "1.0"){


    // struct ERC20Asset{
    //     address token;
    //     uint256 amount;
    // }

    // struct ERC721Asset{
    //     address token;
    //     uint256 tokenId;
    // }

    // struct Order{
    //     address maker;
    //     bool isCall;
    //     bool isLong;
    //     address baseAsset;  //underlying asset
    //     uint256 strike;     // strike price * amount of baseAsset
    //     uint256 premium;    // insurance fee
    //     uint256 duration;
    //     uint256 expiration; // last day to fill this order 
    //     uint256 nonce;      // make sure every order hash is different //!!! be careful 
    //     address[] whitelist;
    //     ERC20Asset[] ERC20Assets;
    //     ERC721Asset[] ERC721Assets;
    // }

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

    function getTypedDataHash(dataStructs.Order memory _order) public returns (bytes32) {
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

    function getERC20AssetsHash(dataStructs.ERC20Asset[] memory assets) internal pure returns (bytes memory assetHash){
        for(uint256 i = 0; i< assets.length; ++i){
            assetHash = abi.encodePacked(assetHash, keccak256(abi.encode(
                    ERC20ASSET_TYPE_HASH,
                    assets[i].token,
                    assets[i].amount
            )));
        }

        return assetHash;
    }

    function getERC721AssetsHash(dataStructs.ERC721Asset[] memory assets) internal pure returns (bytes memory assetHash){
        for(uint256 i = 0; i< assets.length; ++i){
            assetHash = abi.encodePacked(assetHash, keccak256(abi.encode(
                    ERC721ASSET_TYPE_HASH,
                    assets[i].token,
                    assets[i].tokenId
            )));
        }

        return assetHash;
    }
}

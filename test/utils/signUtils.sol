// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../libs/dataStructs.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";


contract sigUtils is EIP712("OptionExchange", "1.0"){

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

    function getTypedDataHash(dataStructs.Order memory _order) public returns (bytes32) {
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

    function getERC20AssetHash(dataStructs.ERC20Asset memory _asset) internal returns (bytes32 assetHash){
        return keccak256(abi.encode(ERC20ASSET_TYPE_HASH, _asset.token, _asset.amount));
    }

    function getERC721AssetHash(dataStructs.ERC721Asset memory _asset) internal returns (bytes32 assetHash){
        return keccak256(abi.encode(ERC721ASSET_TYPE_HASH, _asset.token, _asset.tokenId));
    }
}

pragma solidity ^0.8.0;

library dataStructs{
    
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
        bool isERC20;       // if ture, then the underling is ERC20 asset only 
        address baseAsset;  // token used to pay premium and strike price
        uint256 strike;     // strike price
        uint256 premium;    // insurance fee
        uint256 duration;   // in seconds
        uint256 expiration; // last day to fill this order 
        uint256 nonce;      // make sure every order hash is different
        address[] whitelist;
        ERC20Asset underlyingERC20;
        ERC721Asset underlyingERC721;
    }
}
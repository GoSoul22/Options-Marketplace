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
        address baseAsset;  //underlying asset
        uint256 strike;     // strike price * amount of baseAsset
        uint256 premium;    // insurance fee
        uint256 duration;
        uint256 expiration; // last day to fill this order 
        uint256 nonce;      // make sure every order hash is different //!!! be careful 
        address[] whitelist;
        ERC20Asset[] ERC20Assets;
        ERC721Asset[] ERC721Assets;
    }
}
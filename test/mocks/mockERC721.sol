pragma solidity  ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";


contract MockERC721 is ERC721 {
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    //every one can mint only for testing purpose
    function safeMint(address to, uint256 tokenId) public {
        _safeMint(to, tokenId);
    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/positionNFT.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

error Unauthorized();

contract positionNFTTest is Test, ERC721Holder {
    positionNFT public PNFT;
    address public unauthorizedAddress;

    function setUp() public {
        PNFT = new positionNFT();
        unauthorizedAddress = address(1);
    }

    function testMintAndBurn() public {
        PNFT.safeMint(address(this), 1);
        assertEq(PNFT.balanceOf(address(this)), 1);

        PNFT.burn(1);
        assertEq(PNFT.balanceOf(address(this)), 0);
    }

    function testSafeMintAsNotOwner() public {
        //unauthorized address cannot mint
        vm.expectRevert();
        vm.prank(unauthorizedAddress);
        PNFT.safeMint(address(1), 1);
    }

    function testBurnAsNotOwner() public {
        //unauthorized address cannot burn
        PNFT.safeMint(address(this), 1);
        vm.expectRevert();
        vm.prank(unauthorizedAddress);
        PNFT.burn(1);
    }

    function testTransferOwnership() public {
        PNFT.transferOwnership(unauthorizedAddress);
        assertEq(PNFT.owner(), unauthorizedAddress);
    }

    function testTransferOwnershipAsNotOwner() public{
        //unauthorized address cannot transfer ownership
        assertEq(PNFT.owner(), address(this)); 
        vm.expectRevert();
        vm.prank(unauthorizedAddress);
        PNFT.transferOwnership(address(1));
    }


}

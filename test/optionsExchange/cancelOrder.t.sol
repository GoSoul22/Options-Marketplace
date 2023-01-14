pragma solidity ^0.8.0;


import "forge-std/Test.sol";
import "../utils/signUtils.sol";
import "../mocks/mockERC20.sol";
import "../mocks/mockERC721.sol";
import "../libs/dataStructs.sol";
import "../../src/optionsExchange.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract cancelOrder is Test {

    address internal maker;
    address internal maker2;
    address internal taker;
    address internal taker2;
    uint256 internal makerPrivateKey;
    uint256 internal maker2PrivateKey;
    uint256 internal takerPrivateKey;
    uint256 internal taker2PrivateKey;
    uint256 internal nonceToUse = 90324782215;

    MockERC20 internal baseAsset;
    optionsExchange internal optionsExchangeContract;

    function setUp() public {
        baseAsset = new MockERC20("baseAsset", "baseAsset");

        makerPrivateKey = 0xfb586f856d0a5ff10fd9ec3446dc478c58da9c10f72cfc50ed3b027c051e840f;
        takerPrivateKey = 0xf48675788d61ca922b56ea442d68027968ce3175d58e2cfdbc582130bd58f720;
        maker = vm.addr(makerPrivateKey); //public address: 0xE74D59cCFA9bfCa8F11aFc98E7FfF1d13678E950
        taker = vm.addr(takerPrivateKey); //public address: 0xfa350589Ae705f755483FF8cF709cf4dD33660A8
    }

    function test_cancelOrder() public {

        address[] memory temp = new address[](1);
        temp[0] = address(baseAsset);


        optionsExchangeContract = new optionsExchange(address(1), temp);
        MockERC20 underlying_BTC = new MockERC20("Wrapped BTC", "WBTC");

        optionsExchange.ERC20Asset memory erc20Asset = optionsExchange.ERC20Asset({
            token: address(underlying_BTC),
            amount: 100
        });

        optionsExchange.ERC721Asset memory erc721Asset;


        optionsExchange.ERC721Asset[] memory ERC721temp;
        optionsExchange.Order memory _order = optionsExchange.Order({
            maker: maker,
            isCall: true,
            isLong: true,
            isERC20: true,
            baseAsset: address(baseAsset),
            strike: 100,  
            premium: 10,  
            duration: 10 days,  
            expiration: 100,
            nonce: nonceToUse,
            underlyingERC20: erc20Asset, // only ERC20 assets
            underlyingERC721: erc721Asset  //empty array
        });

        bytes32 orderHash = optionsExchangeContract.getOrderStructHash(_order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, orderHash); //maker signs the order hash
        bytes memory signature = abi.encodePacked(r, s, v); //concatenate r, s, v

        // mint 10 baseAsset to maker(for premium)
        baseAsset.mint(maker, _order.premium);

        //mint 100 WBTC(for the underlying) to taker
        underlying_BTC.mint(taker, _order.underlyingERC20.amount);

        //maker approves 10 baseAsset to optionsExchangeContract
        vm.startPrank(maker);
        baseAsset.approve(address(optionsExchangeContract), _order.premium);
        vm.stopPrank();
        assertEq(baseAsset.allowance(maker, address(optionsExchangeContract)), _order.premium);

        //taker approves 100 WBTC to optionsExchangeContract
        vm.startPrank(taker);
        underlying_BTC.approve(address(optionsExchangeContract), _order.underlyingERC20.amount);
        vm.stopPrank();
        assertEq(underlying_BTC.allowance(taker, address(optionsExchangeContract)), 100);

        //**Order maker cancels this order */
        vm.startPrank(maker);
        optionsExchangeContract.cancelOrder(_order);
        vm.stopPrank();

        //**Make sure no one can fill this order */
        //taker fills the order
        vm.startPrank(taker);
        vm.expectRevert("Order has been cancelled");
        (uint256 makerNFT, uint256 takerNFT) = optionsExchangeContract.fillOrder(_order, signature);
        vm.stopPrank();

        //check the balance of maker and taker
        IERC721 PNFT = IERC721(address(optionsExchangeContract.PNFT()));
        assertEq(PNFT.balanceOf(maker), 0);
        assertEq(PNFT.balanceOf(taker), 0);
    }
}
pragma solidity ^0.8.0;

// Short Put Order Maker: 
//     1. order maker receives a premium for writing an option from msg.sender(taker). -> transfer premium from msg.sender(is long) to order maker(is short)
//     2. order maker is obligated to buy the underlying at the strike price from the option owner.   -> transfer strike(WETH/DAI) from order maker to contract
//     3. order maker can withdraw the underlying(ERC20/ERC721)

import "forge-std/Test.sol";
import "../mocks/mockERC20.sol";
import "../mocks/mockERC721.sol";
import "../libraries/dataStructs.sol";
import "../../src/optionsExchange.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract shortPut is Test{

    address internal maker;
    address internal maker2;
    address internal taker;
    address internal taker2;
    uint256 internal makerPrivateKey;
    uint256 internal maker2PrivateKey;
    uint256 internal takerPrivateKey;
    uint256 internal taker2PrivateKey;

    MockERC20 internal baseAsset;

    address[] whitelists;
    dataStructs.ERC20Asset[] ERC20Assets;
    dataStructs.ERC721Asset[] ERC721Assets;

    optionsExchange internal optionsExchangeContract;

    function setUp() public {

        baseAsset = new MockERC20("baseAsset", "baseAsset");

        makerPrivateKey = 0xfb586f856d0a5ff10fd9ec3446dc478c58da9c10f72cfc50ed3b027c051e840f;
        maker2PrivateKey = 0x13fd17e03637714364d8ec68d825e42ee148bb5ad2e7d5ddf5891013da4f60ce;
        takerPrivateKey = 0xf48675788d61ca922b56ea442d68027968ce3175d58e2cfdbc582130bd58f720;
        taker2PrivateKey = 0x41946502ffc6ddf6c3e2644f3010159a9e06262c6b0d2edea6f10b25636b6c2d;
        maker = vm.addr(makerPrivateKey); //public address: 0xE74D59cCFA9bfCa8F11aFc98E7FfF1d13678E950
        maker2 = vm.addr(maker2PrivateKey); //public address: 
        taker = vm.addr(takerPrivateKey); //public address: 0xfa350589Ae705f755483FF8cF709cf4dD33660A8
        taker2 = vm.addr(taker2PrivateKey); //public address:

        whitelists = [taker, 0xD52f027222A40C1a385263284D5aEC42DCEA5020, 0x8ca92E1f31914745a4D7665Db36D340A820BFB25];
    }

// Short Put Order Maker: 
//     1. order maker receives a premium for writing an option from msg.sender(taker). 
//                      -> transfer premium from msg.sender(is long) to order maker(is short)
//     2. order maker is obligated to buy the underlying at the strike price from the option owner.   
//                      -> transfer strike(WETH/DAI) from order maker to contract
//     3. condition 1: if the price falls below the strike price, the option owner can exercise the option and sell the underlying to the order maker. 
//                      -> sell: transfer the underlying from option owner to contract (exerciseOrder())
//                      -> transfer the strike from contract to order maker (exerciseOrder())
//                      -> transfer the strike from contract to order taker (withdrawOrder())
//     4. condition 2: if the price rises above the strike price, the order taker can withdraw the strike from the contract.


    function test_ShortPut_Condition_One() public {

        address[] memory temp = new address[](1);
        temp[0] = address(baseAsset);


        optionsExchangeContract = new optionsExchange(address(1), temp);
        MockERC20 underlying_BTC = new MockERC20("Wrapped BTC", "WBTC");

        optionsExchange.ERC20Asset[] memory erc20Assets = new optionsExchange.ERC20Asset[](1);
        erc20Assets[0] = optionsExchange.ERC20Asset({
            token: address(underlying_BTC),
            amount: 100
        });

        optionsExchange.ERC721Asset[] memory ERC721temp;
        optionsExchange.Order memory _order = optionsExchange.Order({
            maker: maker,
            isCall: false,
            isLong: false,
            baseAsset: address(baseAsset),
            strike: 100,  
            premium: 10,  
            duration: 10 days,  
            expiration: 100,
            nonce: block.timestamp,
            whitelist: whitelists,
            ERC20Assets: erc20Assets, // only ERC20 assets
            ERC721Assets: ERC721temp  //empty array
        });

        bytes32 orderHash = optionsExchangeContract.getOrderStructHash(_order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, orderHash); //maker signs the order hash
        bytes memory signature = abi.encodePacked(r, s, v); //concatenate r, s, v


        // mint baseAsset to taker(for premium)
        baseAsset.mint(taker, _order.premium);
        // mint baseAsset to maker(for strike)
        baseAsset.mint(maker, _order.strike);

        //maker approves _order.strike to optionsExchangeContract
        vm.startPrank(maker);
        baseAsset.approve(address(optionsExchangeContract), _order.strike);
        vm.stopPrank();

        //taker fills the order
        vm.startPrank(taker);
        baseAsset.approve(address(optionsExchangeContract), _order.premium);
        (uint256 makerNFT, uint256 takerNFT) = optionsExchangeContract.fillOrder(_order, signature);
        vm.stopPrank();

        //check the balance of maker and taker
        IERC721 PNFT = IERC721(address(optionsExchangeContract.PNFT()));
        assertEq(PNFT.balanceOf(maker), 1);
        assertEq(PNFT.balanceOf(taker), 1);
        assertEq(PNFT.ownerOf(makerNFT), maker);
        assertEq(PNFT.ownerOf(takerNFT), taker);

        assertEq(baseAsset.balanceOf(maker), _order.premium);
        assertEq(baseAsset.balanceOf(taker), 0);
        assertEq(baseAsset.balanceOf(address(optionsExchangeContract)), _order.strike);


//     3. condition 1: if the price drops below the strike price, the order taker can exercise the option and sell the underlying to the order maker. 
//                      -> sell: transfer the underlying from taker to contract (exerciseOrder())
//                      -> pay: transfer the strike from contract to order taker (exerciseOrder())
//                      -> transfer the underlying from contract to order maker (withdrawOrder())

        //** Order taker exercises this order */
        optionsExchange.Order memory _oppsiteOrder = optionsExchange.Order({
            maker: maker,
            isCall: false,
            isLong: true,
            baseAsset: address(baseAsset),
            strike: 100,  
            premium: 10,  
            duration: 10 days,  
            expiration: 100,
            nonce: block.timestamp,
            whitelist: whitelists,
            ERC20Assets: erc20Assets, // only ERC20 assets
            ERC721Assets: ERC721temp  //empty array
        });
        //mint 100 WBTC to order taker 
        underlying_BTC.mint(taker, _order.ERC20Assets[0].amount);

        vm.startPrank(taker);
        PNFT.approve(address(optionsExchangeContract), takerNFT);
        underlying_BTC.approve(address(optionsExchangeContract), _order.ERC20Assets[0].amount);
        optionsExchangeContract.exerciseOrder(_oppsiteOrder);
        vm.stopPrank();

        //check the balance of maker and taker
        assertEq(PNFT.balanceOf(maker), 1);
        assertEq(PNFT.balanceOf(taker), 0);
        assertEq(PNFT.ownerOf(makerNFT), maker);

        assertEq(baseAsset.balanceOf(maker), _order.premium);
        assertEq(baseAsset.balanceOf(taker), _order.strike);

        assertEq(underlying_BTC.balanceOf(maker), 0); 
        assertEq(underlying_BTC.balanceOf(taker), 0); 
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), _order.ERC20Assets[0].amount);

         //** Order maker withdraws this order */

        vm.startPrank(maker);
        PNFT.approve(address(optionsExchangeContract), makerNFT);
        optionsExchangeContract.withdrawOrder(_order);
        vm.stopPrank();

        //check the balance of maker and the contract
        assertEq(PNFT.balanceOf(maker), 0);
        assertEq(PNFT.balanceOf(taker), 0);

        assertEq(baseAsset.balanceOf(address(optionsExchangeContract)), 0);
        assertEq(baseAsset.balanceOf(maker), _order.premium);

        assertEq(underlying_BTC.balanceOf(taker), 0);
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), 0);
        assertEq(underlying_BTC.balanceOf(maker), _order.ERC20Assets[0].amount); 
    }

}
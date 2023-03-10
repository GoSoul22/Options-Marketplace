pragma solidity ^0.8.0;


import "forge-std/Test.sol";
import "../utils/signUtils.sol";
import "../mocks/mockERC20.sol";
import "../mocks/mockERC721.sol";
import "../libs/dataStructs.sol";
import "../../src/optionsExchange.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract longCall is Test {

    address internal maker;
    address internal maker2;
    address internal taker;
    address internal taker2;
    uint256 internal makerPrivateKey;
    uint256 internal maker2PrivateKey;
    uint256 internal takerPrivateKey;
    uint256 internal taker2PrivateKey;

    uint256 internal nonceToUse = 789233;

    MockERC20 internal baseAsset;

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
    }

    //Long Call Maker:
    // 1. order maker pays a premium to the msg.sender -> transfer premium from maker(is long) to msg.sender(is short)
    // 2. If the price rises above the strike price, order maker has the right to buy the underlying at the strike price. -> transfer the underlying from msg.sender to contract
    // 3. condition 1: the price rises above the strike price: order maker will buy the underlying at the strike price. 
    //      -> transfer the strike from order maker to contract.
    //      -> transfer the strike from contract to order taker(msg.sender) when function withdrawOrder() is called.
    // 4. condition 2: the price drops below the strike price: order maker will not buy the underlying at the strike price.
    //      -> transfer the underlying from contract to order taker(msg.sender) when function withdrawOrder() is called.
    function test_LongCall_Condition_One() public {

        address[] memory temp = new address[](1);
        temp[0] = address(baseAsset);


        optionsExchangeContract = new optionsExchange(address(1), temp);
        MockERC20 underlying_BTC = new MockERC20("Wrapped BTC", "WBTC");

        optionsExchange.ERC20Asset memory erc20Asset = optionsExchange.ERC20Asset({
            token: address(underlying_BTC),
            amount: 100
        });

        optionsExchange.ERC721Asset memory ERC721temp;
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
            underlyingERC721: ERC721temp  //empty array
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
        // emit log_uint(baseAsset.allowance(maker, address(optionsExchangeContract)));

        //taker approves 100 WBTC to optionsExchangeContract
        vm.startPrank(taker);
        underlying_BTC.approve(address(optionsExchangeContract), _order.underlyingERC20.amount);
        vm.stopPrank();
        assertEq(underlying_BTC.allowance(taker, address(optionsExchangeContract)), 100);
        // emit log_uint(underlying_BTC.allowance(taker, address(optionsExchangeContract)));


        //taker fills the order
        vm.startPrank(taker);
        (uint256 makerNFT, uint256 takerNFT) = optionsExchangeContract.fillOrder(_order, signature);
        vm.stopPrank();

        //check the balance of maker and taker
        IERC721 PNFT = IERC721(address(optionsExchangeContract.PNFT()));
        assertEq(PNFT.balanceOf(maker), 1);
        assertEq(PNFT.balanceOf(taker), 1);
        assertEq(PNFT.ownerOf(makerNFT), maker);
        assertEq(PNFT.ownerOf(takerNFT), taker);

        assertEq(baseAsset.balanceOf(maker), 0);
        assertEq(baseAsset.balanceOf(taker), _order.premium);

        assertEq(underlying_BTC.balanceOf(taker), 0);
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), _order.strike);
        
        // 3. condition 1: the price raises above the strike price: order maker will buy the underlying at the strike price. 
        //      -> transfer the underlying from order taker(msg.sender) to contract.
        //      -> transfer the underlying from contract to order maker or msg.sender if PNFT is transferred.
        //      -> transfer the strike from contract to order taker(msg.sender) when function withdrawOrder() is called. 

        //** Order maker exercises this order */
        //mint 100 baseAsset to order maker 
        baseAsset.mint(maker, _order.strike);// for the strike

        vm.startPrank(maker);
        PNFT.approve(address(optionsExchangeContract), makerNFT);
        baseAsset.approve(address(optionsExchangeContract), _order.strike);
        optionsExchangeContract.exerciseOrder(_order);
        vm.stopPrank();

        //check the balance of maker and taker
        assertEq(PNFT.balanceOf(maker), 0);
        assertEq(PNFT.balanceOf(taker), 1);
        assertEq(PNFT.ownerOf(takerNFT), taker);

        assertEq(baseAsset.balanceOf(maker), 0);
        assertEq(baseAsset.balanceOf(address(optionsExchangeContract)), _order.strike);

        assertEq(underlying_BTC.balanceOf(maker), _order.underlyingERC20.amount); 
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), 0);

         //** Order taker withdraws this order */
        optionsExchange.Order memory _oppsiteOrder = optionsExchange.Order({
            maker: maker,
            isCall: true,
            isLong: false,
            isERC20: true,
            baseAsset: address(baseAsset),
            strike: 100,  
            premium: 10,  
            duration: 10 days,  
            expiration: 100,
            nonce: nonceToUse,
            underlyingERC20: erc20Asset, // only ERC20 assets
            underlyingERC721: ERC721temp  //empty array
        });

        vm.startPrank(taker);
        PNFT.approve(address(optionsExchangeContract), takerNFT);
        optionsExchangeContract.withdrawOrder(_oppsiteOrder);
        vm.stopPrank();

        //check the balance of taker and the contract
        assertEq(PNFT.balanceOf(taker), 0);

        assertEq(baseAsset.balanceOf(address(optionsExchangeContract)), 0);
        assertEq(baseAsset.balanceOf(taker), _order.strike + _order.premium);

        assertEq(underlying_BTC.balanceOf(taker), 0);
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), 0);
        assertEq(underlying_BTC.balanceOf(maker), _order.underlyingERC20.amount); 
    }

    function test_LongCall_Condition_One_WithMakerNFTTransferred() public {

        address[] memory temp = new address[](1);
        temp[0] = address(baseAsset);

        optionsExchangeContract = new optionsExchange(address(1), temp);
        MockERC20 underlying_BTC = new MockERC20("Wrapped BTC", "WBTC");

        optionsExchange.ERC20Asset memory erc20Asset = optionsExchange.ERC20Asset({
            token: address(underlying_BTC),
            amount: 100
        });

        optionsExchange.ERC721Asset memory ERC721Empty;
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
            underlyingERC721: ERC721Empty  //empty array
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
        // emit log_uint(baseAsset.allowance(maker, address(optionsExchangeContract)));

        //taker approves 100 WBTC to optionsExchangeContract
        vm.startPrank(taker);
        underlying_BTC.approve(address(optionsExchangeContract), _order.underlyingERC20.amount);
        vm.stopPrank();
        assertEq(underlying_BTC.allowance(taker, address(optionsExchangeContract)), 100);
        // emit log_uint(underlying_BTC.allowance(taker, address(optionsExchangeContract)));


        //taker fills the order
        vm.startPrank(taker);
        (uint256 makerNFT, uint256 takerNFT) = optionsExchangeContract.fillOrder(_order, signature);
        vm.stopPrank();

        //check the balance of maker and taker
        IERC721 PNFT = IERC721(address(optionsExchangeContract.PNFT()));
        assertEq(PNFT.balanceOf(maker), 1);
        assertEq(PNFT.balanceOf(taker), 1);
        assertEq(PNFT.ownerOf(makerNFT), maker);
        assertEq(PNFT.ownerOf(takerNFT), taker);

        assertEq(baseAsset.balanceOf(maker), 0);
        assertEq(baseAsset.balanceOf(taker), _order.premium);
        assertEq(baseAsset.balanceOf(address(optionsExchangeContract)), 0);

        assertEq(underlying_BTC.balanceOf(taker), 0);
        assertEq(underlying_BTC.balanceOf(maker), 0);
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), _order.strike);
        
        // 3. condition 1: the price raises above the strike price: order maker will buy the underlying at the strike price. 
        //      -> transfer the underlying from order taker(msg.sender) to contract.
        //      -> transfer the underlying from contract to order maker or msg.sender if PNFT is transferred.
        //      -> transfer the strike from contract to order taker(msg.sender) when function withdrawOrder() is called. 

        //** Order maker transfers makerNFT */
        vm.startPrank(maker);
        PNFT.safeTransferFrom(maker, maker2, makerNFT);
        vm.stopPrank();
        assertEq(PNFT.balanceOf(maker), 0);


        //make sure maker cannot exercise the order any more
        vm.startPrank(maker);
        vm.expectRevert("ERC721: approve caller is not token owner or approved for all");
        PNFT.approve(address(optionsExchangeContract), takerNFT);
        vm.expectRevert("Only long position owner can exercise or order has been exercised");
        optionsExchangeContract.exerciseOrder(_order);
        vm.stopPrank();

        //** Order maker2 exercises this order */
        //mint 100 baseAsset to order maker2 
        baseAsset.mint(maker2, _order.strike);// for the strike

        vm.startPrank(maker2);
        PNFT.approve(address(optionsExchangeContract), makerNFT);
        baseAsset.approve(address(optionsExchangeContract), _order.strike);
        optionsExchangeContract.exerciseOrder(_order);
        vm.stopPrank();

        //check the balance of maker2 and taker
        assertEq(PNFT.balanceOf(maker2), 0);
        assertEq(PNFT.balanceOf(taker), 1);
        assertEq(PNFT.ownerOf(takerNFT), taker);

        assertEq(baseAsset.balanceOf(maker2), 0);
        assertEq(baseAsset.balanceOf(address(optionsExchangeContract)), _order.strike);

        assertEq(underlying_BTC.balanceOf(maker2), _order.underlyingERC20.amount); 
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), 0);

         //** Order taker withdraws this order */
        optionsExchange.Order memory _oppsiteOrder = optionsExchange.Order({
            maker: maker,
            isCall: true,
            isLong: false,
            isERC20: true,
            baseAsset: address(baseAsset),
            strike: 100,  
            premium: 10,  
            duration: 10 days,  
            expiration: 100,
            nonce: nonceToUse,
            underlyingERC20: erc20Asset, // only ERC20 assets
            underlyingERC721: ERC721Empty  //empty array
        });

        vm.startPrank(taker);
        PNFT.approve(address(optionsExchangeContract), takerNFT);
        optionsExchangeContract.withdrawOrder(_oppsiteOrder);
        vm.stopPrank();

        //check the balance of taker and the contract
        assertEq(PNFT.balanceOf(taker), 0);

        assertEq(baseAsset.balanceOf(address(optionsExchangeContract)), 0);
        assertEq(baseAsset.balanceOf(taker), _order.strike + _order.premium);

        assertEq(underlying_BTC.balanceOf(taker), 0);
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), 0);
        assertEq(underlying_BTC.balanceOf(maker2), _order.underlyingERC20.amount); 
    }


    function test_LongCall_Condition_Two() public {

        address[] memory temp = new address[](1);
        temp[0] = address(baseAsset);


        optionsExchangeContract = new optionsExchange(address(1), temp);
        MockERC20 underlying_BTC = new MockERC20("Wrapped BTC", "WBTC");

        optionsExchange.ERC20Asset memory erc20Asset = optionsExchange.ERC20Asset({
            token: address(underlying_BTC),
            amount: 100
        });

        optionsExchange.ERC721Asset memory ERC721temp;
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
            underlyingERC721: ERC721temp  //empty array
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


        //taker fills the order
        vm.startPrank(taker);
        (uint256 makerNFT, uint256 takerNFT) = optionsExchangeContract.fillOrder(_order, signature);  //!!!!fillorder
        vm.stopPrank();

        //check the balance of maker and taker
        IERC721 PNFT = IERC721(address(optionsExchangeContract.PNFT()));
        assertEq(PNFT.balanceOf(maker), 1);
        assertEq(PNFT.balanceOf(taker), 1);
        assertEq(PNFT.ownerOf(makerNFT), maker);
        assertEq(PNFT.ownerOf(takerNFT), taker);

        assertEq(baseAsset.balanceOf(maker), 0);
        assertEq(baseAsset.balanceOf(taker), _order.premium);

        assertEq(underlying_BTC.balanceOf(taker), 0);
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), _order.strike);

        // 4. condition 2: If the price drops below the strike price: order maker will not buy the underlying at the strike price.
        //      -> transfer the underlying from contract to order taker(msg.sender) when function withdrawOrder() is called.

         //** Order maker does not exercise this order */
        vm.warp(block.timestamp + _order.duration + 1 seconds); // fast forward one second past the deadline

         //** Order taker withdraws this order */
        optionsExchange.Order memory _oppsiteOrder = optionsExchange.Order({
            maker: maker,
            isCall: true,
            isLong: false,
            isERC20: true,
            baseAsset: address(baseAsset),
            strike: 100,  
            premium: 10,  
            duration: 10 days,  
            expiration: 100,
            nonce: nonceToUse,
            underlyingERC20: erc20Asset, // only ERC20 assets
            underlyingERC721: ERC721temp  //empty array
        });

        vm.startPrank(taker);                                     
        PNFT.approve(address(optionsExchangeContract), takerNFT); 
        optionsExchangeContract.withdrawOrder(_oppsiteOrder); 
        vm.stopPrank();

        //check the balance of taker and the contract
        assertEq(PNFT.balanceOf(taker), 0);

        assertEq(baseAsset.balanceOf(address(optionsExchangeContract)), 0);
        assertEq(baseAsset.balanceOf(taker), _order.premium);

        assertEq(underlying_BTC.balanceOf(maker), 0);
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), 0);
        assertEq(underlying_BTC.balanceOf(taker), _order.underlyingERC20.amount); 
    }

    function test_LongCall_Condition_Two_WithTakerNFTTransferred() public {

        address[] memory temp = new address[](1);
        temp[0] = address(baseAsset);


        optionsExchangeContract = new optionsExchange(address(1), temp);
        MockERC20 underlying_BTC = new MockERC20("Wrapped BTC", "WBTC");

        optionsExchange.ERC20Asset memory erc20Asset = optionsExchange.ERC20Asset({
            token: address(underlying_BTC),
            amount: 100
        });

        optionsExchange.ERC721Asset memory ERC721temp;
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
            underlyingERC721: ERC721temp  //empty array
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


        //taker fills the order
        vm.startPrank(taker);
        (uint256 makerNFT, uint256 takerNFT) = optionsExchangeContract.fillOrder(_order, signature);
        vm.stopPrank();

        //check the balance of maker and taker
        IERC721 PNFT = IERC721(address(optionsExchangeContract.PNFT()));
        assertEq(PNFT.balanceOf(maker), 1);
        assertEq(PNFT.balanceOf(taker), 1);
        assertEq(PNFT.ownerOf(makerNFT), maker);
        assertEq(PNFT.ownerOf(takerNFT), taker);

        assertEq(baseAsset.balanceOf(maker), 0);
        assertEq(baseAsset.balanceOf(taker), _order.premium);

        assertEq(underlying_BTC.balanceOf(taker), 0);
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), _order.strike);

        // 4. condition 2: If the price drops below the strike price: order maker will not buy the underlying at the strike price.
        //      -> transfer the underlying from contract to order taker(msg.sender) when function withdrawOrder() is called.

         //** Order maker did not exercise this order */
        vm.warp(block.timestamp + _order.duration + 1 seconds); // fast forward one second past the deadline

         //** Order taker withdraws this order */
        optionsExchange.Order memory _oppsiteOrder = optionsExchange.Order({
            maker: maker,
            isCall: true,
            isLong: false,
            isERC20: true,
            baseAsset: address(baseAsset),
            strike: 100,  
            premium: 10,  
            duration: 10 days,  
            expiration: 100,
            nonce: nonceToUse,
            underlyingERC20: erc20Asset, // only ERC20 assets
            underlyingERC721: ERC721temp  //empty array
        });

        //make sure order maker cannot call function exerciseOrder() because the order has expired.
        vm.startPrank(maker);
        PNFT.approve(address(optionsExchangeContract), makerNFT);
        vm.expectRevert("Order has expired");
        optionsExchangeContract.exerciseOrder(_order);
        vm.stopPrank();


        vm.startPrank(taker);
        PNFT.safeTransferFrom(taker, taker2, takerNFT);
        vm.stopPrank();
        assertEq(PNFT.balanceOf(taker), 0);
        
        vm.startPrank(taker2);
        PNFT.approve(address(optionsExchangeContract), takerNFT);
        optionsExchangeContract.withdrawOrder(_oppsiteOrder); 
        vm.stopPrank();

        assertEq(baseAsset.balanceOf(taker), _order.premium);


        //check the balance of taker and the contract
        assertEq(PNFT.balanceOf(taker2), 0);
        assertEq(baseAsset.balanceOf(address(optionsExchangeContract)), 0);

        assertEq(underlying_BTC.balanceOf(maker), 0);
        assertEq(underlying_BTC.balanceOf(address(optionsExchangeContract)), 0);
        assertEq(underlying_BTC.balanceOf(taker2), _order.underlyingERC20.amount); 

        // make sure taker cannot call function withdrawOrder()
        vm.startPrank(taker);
        vm.expectRevert("ERC721: invalid token ID");
        PNFT.approve(address(optionsExchangeContract), takerNFT);
        vm.expectRevert("ERC721: invalid token ID");
        optionsExchangeContract.withdrawOrder(_oppsiteOrder);
        vm.stopPrank();

    }

}


// Sets an address' balance
    // function deal(address who, uint256 newBalance) external;
    //vm.deal(maker/taker, _order.premium/_order.strike);
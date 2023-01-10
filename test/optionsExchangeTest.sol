pragma solidity ^0.8.0;


import "forge-std/Test.sol";
import "./utils/signUtils.sol";
import "./mocks/mockERC20.sol";
import "./mocks/mockERC721.sol";
import "./libraries/dataStructs.sol";
import "../src/optionsExchange.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract optionsExchangeTest is Test {

    address internal maker;
    address internal taker;
    uint256 internal makerPrivateKey;
    uint256 internal takerPrivateKey;

    sigUtils internal sigUtil;
    MockERC20 internal baseAsset;

    address[] whitelists;
    dataStructs.ERC20Asset[] ERC20Assets;
    dataStructs.ERC721Asset[] ERC721Assets;

    optionsExchange internal optionsExchangeContract;

    function setUp() public {

        // sigUtil = new sigUtils();
        baseAsset = new MockERC20("baseAsset", "baseAsset");

        makerPrivateKey = 0xfb586f856d0a5ff10fd9ec3446dc478c58da9c10f72cfc50ed3b027c051e840f;
        takerPrivateKey = 0xf48675788d61ca922b56ea442d68027968ce3175d58e2cfdbc582130bd58f720;
        maker = vm.addr(makerPrivateKey); //0xE74D59cCFA9bfCa8F11aFc98E7FfF1d13678E950
        taker = vm.addr(takerPrivateKey); //0xfa350589Ae705f755483FF8cF709cf4dD33660A8

        whitelists = [taker, 0xD52f027222A40C1a385263284D5aEC42DCEA5020, 0x8ca92E1f31914745a4D7665Db36D340A820BFB25];

        // for(uint256 i = 0; i < 11; i++){
        //     MockERC20 token = new MockERC20("mockERC20Name", "mockERC20Symbol");
        //     ERC20Assets.push(dataStructs.ERC20Asset({
        //         token: address(token),
        //         amount: 100
        //     }));
        // }

        // for(uint256 i = 0; i < 10; i++){
        //     MockERC721 token = new MockERC721("mockERC721Name", "mockERC721Symbol");
        //     ERC721Assets.push(dataStructs.ERC721Asset({
        //         token: address(token),
        //         tokenId: 100
        //     }));
        // }
    }

    //Long Call Maker:
    // 1. order maker pays a premium to the msg.sender -> transfer premium from maker(is long) to msg.sender(is short)
    // 2. If the price raises above the strike price, order maker has the right to buy the underlying at the strike price. -> transfer the underlying from msg.sender to contract
    function testFillOrder_LongCall() public {

        address[] memory temp = new address[](1);
        temp[0] = address(baseAsset);


        optionsExchangeContract = new optionsExchange(address(1), temp);
        MockERC20 underlying_BTC = new MockERC20("Wrapped BTC", "WBTC");

        optionsExchange.ERC20Asset[] memory erc20Assets = new optionsExchange.ERC20Asset[](1);
        erc20Assets[0] = optionsExchange.ERC20Asset({
            token: address(underlying_BTC),
            amount: 100
        });


        // mint 10 baseAsset to maker(for premium)
        baseAsset.mint(maker, 10);

        //mint 100 WBTC(underlying) to taker
        underlying_BTC.mint(taker, 100);


        //maker approves 10 baseAsset to optionsExchangeContract
        vm.startPrank(maker);
        baseAsset.approve(address(optionsExchangeContract), 10);
        vm.stopPrank();
        assertEq(baseAsset.allowance(maker, address(optionsExchangeContract)), 10);
        emit log_uint(baseAsset.allowance(maker, address(optionsExchangeContract)));


        //taker approves 100 WBTC to optionsExchangeContract
        vm.startPrank(taker);
        underlying_BTC.approve(address(optionsExchangeContract), 100);
        vm.stopPrank();
        assertEq(underlying_BTC.allowance(taker, address(optionsExchangeContract)), 100);
        emit log_uint(underlying_BTC.allowance(taker, address(optionsExchangeContract)));


        optionsExchange.ERC721Asset[] memory ERC721temp;
        optionsExchange.Order memory _order = optionsExchange.Order({
            maker: maker,
            isCall: true,
            isLong: true,
            baseAsset: address(baseAsset),
            strike: 100,  
            premium: 10,  
            duration: 10,  
            expiration: 100,
            nonce: block.timestamp,
            whitelist: whitelists,
            ERC20Assets: erc20Assets,
            ERC721Assets: ERC721temp
        });

        bytes32 orderHash = optionsExchangeContract.getOrderStructHash(_order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, orderHash); //maker signs the order
        bytes memory signature = abi.encodePacked(r, s, v); 


        //taker fills the order
        vm.startPrank(taker);
        assertTrue(_order.isLong);
        optionsExchangeContract.fillOrder(_order, signature);
        vm.stopPrank();

        //check the balance of maker and taker
        address PNFT = address(optionsExchangeContract.PNFT());
        assertEq(IERC721(PNFT).balanceOf(maker), 1);
        assertEq(IERC721(PNFT).balanceOf(taker), 1);

        //MockERC20::transferFrom(0xfa350589Ae705f755483FF8cF709cf4dD33660A8, 0xE74D59cCFA9bfCa8F11aFc98E7FfF1d13678E950, 10) 
        // -> transfer 10 baseAsset from taker to maker
    }
}
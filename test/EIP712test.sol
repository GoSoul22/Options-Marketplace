pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./utils/signUtils.sol";
import "./mocks/mockERC20.sol";
import "./mocks/mockERC721.sol";
import "./libraries/dataStructs.sol";

import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";


contract EIP712Test is Test {

    uint256 internal makerPrivateKey;
    uint256 internal takerPrivateKey;

    address internal maker;
    address internal taker;
    sigUtils internal sigUtil;
    MockERC20 internal baseAsset;


    address[] whitelists;
    dataStructs.ERC20Asset[] ERC20Assets;
    dataStructs.ERC721Asset[] ERC721Assets;

    function setUp() public {
        
        sigUtil = new sigUtils();
        baseAsset = new MockERC20("baseAsset", "baseAsset");

        makerPrivateKey = 1;
        takerPrivateKey = 2;

        maker = vm.addr(makerPrivateKey);
        taker = vm.addr(takerPrivateKey);

        whitelists = [taker];

        for(uint256 i = 0; i < 10; i++){
            MockERC20 token = new MockERC20("mockERC20Name", "mockERC20Symbol");
            ERC20Assets.push(dataStructs.ERC20Asset({
                token: address(token),
                amount: 100
            }));
        }

        for(uint256 i = 0; i < 10; i++){
            MockERC721 token = new MockERC721("mockERC721Name", "mockERC721Symbol");
            ERC721Assets.push(dataStructs.ERC721Asset({
                token: address(token),
                tokenId: 100
            }));
        }

    }



    function testTypedStructedData_AsMaker() public {
        dataStructs.Order memory order = dataStructs.Order({
            maker: maker,
            isCall: true,
            isLong: true,
            baseAsset: address(baseAsset),
            strike: 100,
            premium: 10,
            duration: 100,
            expiration: 100,
            nonce: 1,  
            whitelist: whitelists,
            ERC20Assets: ERC20Assets,
            ERC721Assets: ERC721Assets
        });

        bytes32 orderHash = sigUtil.getTypedDataHash(order);


        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPrivateKey, orderHash); 
        assertEq(ecrecover(orderHash, v,r,s), maker);
        
        emit log_uint(v);  
        emit log_bytes32(r);  
        emit log_bytes32(s);  

        bytes memory signature = abi.encodePacked(r, s, v);
     
        assertTrue(SignatureChecker.isValidSignatureNow(order.maker, orderHash, signature));

    }

    function testTypedStructedData_AsTaker() public {
        dataStructs.Order memory order = dataStructs.Order({
            maker: maker,
            isCall: true,
            isLong: false,
            baseAsset: address(baseAsset),
            strike: 100,
            premium: 10,
            duration: 100,
            expiration: 100,
            nonce: 12,  
            whitelist: whitelists,
            ERC20Assets: ERC20Assets,
            ERC721Assets: ERC721Assets
        });

        bytes32 orderHash = sigUtil.getTypedDataHash(order);


        (uint8 v, bytes32 r, bytes32 s) = vm.sign(takerPrivateKey, orderHash); 
        assertEq(ecrecover(orderHash, v,r,s), taker);
        
        emit log_uint(v);  
        emit log_bytes32(r);  
        emit log_bytes32(s);  

        bytes memory signature = abi.encodePacked(r, s, v);
     
        assertTrue(!SignatureChecker.isValidSignatureNow(order.maker, orderHash, signature));

    }
}
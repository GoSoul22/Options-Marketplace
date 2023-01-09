pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./utils/signUtils.sol";
import "./mocks/mockERC20.sol";
import "./mocks/mockERC721.sol";
import "./libraries/dataStructs.sol";

// import "../src/optionsExchange.sol";

// import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
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

        for(uint256 i = 0; i < 1; i++){
            MockERC20 token = new MockERC20("mockERC20Name", "mockERC20Symbol");
            ERC20Assets.push(dataStructs.ERC20Asset({
                token: address(token),
                amount: 100
            }));
        }

        for(uint256 i = 0; i < 1; i++){
            MockERC721 token = new MockERC721("mockERC721Name", "mockERC721Symbol");
            ERC721Assets.push(dataStructs.ERC721Asset({
                token: address(token),
                tokenId: 100
            }));
        }

    }



    function test_typedStructedData() public {
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
        vm.startPrank(maker);
        bytes32 signature = ECDSA.toEthSignedMessageHash(orderHash);
        vm.stopPrank();


        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, orderHash);
        address signer = ecrecover(orderHash, v,r,s);
        // assertEq(address(1), maker);
        
        // assertTrue(SignatureChecker.isValidSignatureNow(order.maker, orderHash, bytes.concat(signature)));

    }
}
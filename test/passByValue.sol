// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";


contract PassByValue is Test {

    User public user;

    struct User {
        string name;
        uint age;
    }

    function setUp() public {
        user = User({
            name: "Alice",
            age: 100
        });
    }

    function setUser(User memory _user) public {
        _user.name = "Alice";
        _user.age = 30;
    }

    function testPassByValue() public {
        setUser(user);
        assertEq(user.name, "Alice");
        assertEq(user.age, 100);
    }


}

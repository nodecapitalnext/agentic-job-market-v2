// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "forge-std/Test.sol";
import "../src/ArcGreeter.sol";
contract ArcGreeterTest is Test {
    ArcGreeter arcGreeter;
    function setUp() public { arcGreeter = new ArcGreeter(); }
    function testInitialMessage() public view { assertEq(arcGreeter.getMessage(), "Hello Arc Testnet!"); }
    function testSetMessage() public { arcGreeter.setMessage("Merhaba Arc!"); assertEq(arcGreeter.getMessage(), "Merhaba Arc!"); }
}

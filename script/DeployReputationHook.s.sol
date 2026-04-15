// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "forge-std/Script.sol";
import "../src/ReputationHook.sol";
contract DeployReputationHook is Script {
    function run() external {
        address marketAddress = 0xc71d4C46f30e43b5cEFcD0dDdDfc1A9ae88d5560;
        vm.startBroadcast();
        ReputationHook hook = new ReputationHook(marketAddress);
        vm.stopBroadcast();
        console.log("ReputationHook deployed to:", address(hook));
    }
}

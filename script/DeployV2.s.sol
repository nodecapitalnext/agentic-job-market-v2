// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "forge-std/Script.sol";
import "../src/AgenticJobMarketV2.sol";
contract DeployV2 is Script {
    function run() external {
        address usdc = 0xd6e292C644685ddA32b12aB761ca8D30bBb485D4;
        address feeCollector = 0xc3486d294b102abAC9Da22E2A561c248D6df6584;
        vm.startBroadcast();
        AgenticJobMarketV2 market = new AgenticJobMarketV2(usdc, feeCollector);
        vm.stopBroadcast();
        console.log("AgenticJobMarketV2 deployed to:", address(market));
    }
}

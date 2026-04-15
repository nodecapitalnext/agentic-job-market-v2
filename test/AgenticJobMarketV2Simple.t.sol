// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import "forge-std/Test.sol";
import "../src/AgenticJobMarketV2.sol";
import "../src/MockUSDC.sol";

contract AgenticJobMarketV2SimpleTest is Test {
    AgenticJobMarketV2 public market;
    MockUSDC public usdc;
    address owner = address(this);
    address feeCollector = address(0x999);
    address client = address(0x1);
    address provider = address(0x2);
    address evaluator1 = address(0x3);
    uint256 constant BUDGET = 100 * 1e6;
    uint256 constant EXPIRY = 7 days;
    function setUp() public {
        usdc = new MockUSDC();
        market = new AgenticJobMarketV2(address(usdc), feeCollector);
        vm.prank(client); usdc.mint(10000 * 1e6);
        vm.prank(client); usdc.approve(address(market), type(uint256).max);
    }
    function testCreateJob() public {
        address[] memory evaluators = new address[](1);
        evaluators[0] = evaluator1;
        vm.prank(client);
        uint256 jobId = market.createJob(provider, evaluators, 1, block.timestamp + EXPIRY, "Test job", address(0));
        assertEq(jobId, 0);
    }
    function testFullLifecycle() public {
        address[] memory evaluators = new address[](1);
        evaluators[0] = evaluator1;
        vm.prank(client); uint256 jobId = market.createJob(provider, evaluators, 1, block.timestamp + EXPIRY, "Full lifecycle test", address(0));
        vm.prank(client); market.setBudget(jobId, BUDGET);
        vm.prank(client); market.fund(jobId, BUDGET);
        vm.prank(provider); market.submit(jobId, keccak256("work"));
        vm.prank(evaluator1); market.approve(jobId, keccak256("approved"));
        uint256 platformFee = (BUDGET * 250) / 10000;
        assertEq(usdc.balanceOf(provider), BUDGET - platformFee);
        assertEq(usdc.balanceOf(feeCollector), platformFee);
    }
}

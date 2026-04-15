// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract ReputationHook {
    mapping(address => uint256) public reputation;
    mapping(address => uint256) public completedJobs;
    mapping(address => uint256) public rejectedJobs;
    uint256 public constant MIN_REPUTATION = 50;
    address public jobMarket;
    event ReputationUpdated(address indexed provider, uint256 newReputation);
    constructor(address _jobMarket) { jobMarket = _jobMarket; }
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external {
        require(msg.sender == jobMarket, "Only job market");
        if (selector == bytes4(keccak256("setProvider(uint256,address)"))) {
            address provider = abi.decode(data, (address));
            require(reputation[provider] >= MIN_REPUTATION, "Reputation too low");
        }
    }
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external {
        require(msg.sender == jobMarket, "Only job market");
    }
    function setReputation(address provider, uint256 score) external { reputation[provider] = score; emit ReputationUpdated(provider, score); }
    function recordCompletion(address provider) external { require(msg.sender == jobMarket, "Only job market"); completedJobs[provider]++; reputation[provider] += 10; emit ReputationUpdated(provider, reputation[provider]); }
    function recordRejection(address provider) external { require(msg.sender == jobMarket, "Only job market"); rejectedJobs[provider]++; if (reputation[provider] >= 5) { reputation[provider] -= 5; } emit ReputationUpdated(provider, reputation[provider]); }
    function getProviderStats(address provider) external view returns (uint256 reputationScore, uint256 completed, uint256 rejected, uint256 successRate) {
        reputationScore = reputation[provider]; completed = completedJobs[provider]; rejected = rejectedJobs[provider];
        uint256 total = completed + rejected;
        successRate = total > 0 ? (completed * 100) / total : 0;
    }
}

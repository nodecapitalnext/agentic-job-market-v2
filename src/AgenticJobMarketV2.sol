// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IJobHook {
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
}

contract AgenticJobMarketV2 {
    enum JobState { Open, Funded, Submitted, Completed, Rejected, Expired }
    struct Job {
        uint256 id;
        address client;
        address provider;
        address[] evaluators;
        uint256 requiredApprovals;
        uint256 currentApprovals;
        mapping(address => bool) hasVoted;
        uint256 budget;
        uint256 expiredAt;
        string description;
        bytes32 deliverable;
        JobState state;
        uint256 createdAt;
        address hook;
    }
    struct JobParams {
        address provider;
        address[] evaluators;
        uint256 requiredApprovals;
        uint256 expiredAt;
        string description;
        address hook;
    }
    IERC20 public immutable usdc;
    uint256 public nextJobId;
    mapping(uint256 => Job) internal jobs;
    uint256 public platformFeeBps = 250;
    address public feeCollector;
    uint256 public totalFeesCollected;
    bool public paused;
    address public owner;
    event JobCreated(uint256 indexed jobId, address indexed client, address indexed provider, address[] evaluators, uint256 requiredApprovals, uint256 expiredAt, string description, address hook);
    event BudgetSet(uint256 indexed jobId, uint256 budget);
    event JobFunded(uint256 indexed jobId, address indexed client, uint256 amount);
    event JobSubmitted(uint256 indexed jobId, address indexed provider, bytes32 deliverable);
    event EvaluatorVoted(uint256 indexed jobId, address indexed evaluator, bool approved);
    event JobCompleted(uint256 indexed jobId, uint256 providerAmount, uint256 platformFee);
    event JobRejected(uint256 indexed jobId, address indexed rejector, bytes32 reason);
    event JobExpired(uint256 indexed jobId);
    event PaymentReleased(uint256 indexed jobId, address indexed provider, uint256 amount);
    event Refunded(uint256 indexed jobId, address indexed client, uint256 amount);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollectorUpdated(address oldCollector, address newCollector);
    event Paused(address account);
    event Unpaused(address account);
    modifier onlyOwner() { require(msg.sender == owner, "Only owner"); _; }
    modifier whenNotPaused() { require(!paused, "Contract paused"); _; }
    modifier onlyClient(uint256 jobId) { require(msg.sender == jobs[jobId].client, "Only client"); _; }
    modifier onlyProvider(uint256 jobId) { require(msg.sender == jobs[jobId].provider, "Only provider"); _; }
    modifier onlyEvaluator(uint256 jobId) {
        bool isEvaluator = false;
        for (uint i = 0; i < jobs[jobId].evaluators.length; i++) {
            if (jobs[jobId].evaluators[i] == msg.sender) { isEvaluator = true; break; }
        }
        require(isEvaluator, "Only evaluator");
        _;
    }
    modifier inState(uint256 jobId, JobState expectedState) { require(jobs[jobId].state == expectedState, "Invalid state"); _; }
    constructor(address _usdc, address _feeCollector) {
        require(_usdc != address(0), "Invalid USDC");
        require(_feeCollector != address(0), "Invalid fee collector");
        usdc = IERC20(_usdc);
        feeCollector = _feeCollector;
        owner = msg.sender;
    }
    function createJob(address provider, address[] calldata evaluators, uint256 requiredApprovals, uint256 expiredAt, string calldata description, address hook) external whenNotPaused returns (uint256 jobId) {
        require(evaluators.length > 0, "Need evaluators");
        require(requiredApprovals > 0 && requiredApprovals <= evaluators.length, "Invalid approvals");
        require(expiredAt > block.timestamp, "Invalid expiry");
        require(bytes(description).length > 0, "Empty description");
        jobId = nextJobId++;
        Job storage job = jobs[jobId];
        job.id = jobId; job.client = msg.sender; job.provider = provider;
        job.evaluators = evaluators; job.requiredApprovals = requiredApprovals;
        job.expiredAt = expiredAt; job.description = description;
        job.state = JobState.Open; job.createdAt = block.timestamp; job.hook = hook;
        if (hook != address(0)) IJobHook(hook).beforeAction(jobId, this.createJob.selector, "");
        emit JobCreated(jobId, msg.sender, provider, evaluators, requiredApprovals, expiredAt, description, hook);
        if (hook != address(0)) IJobHook(hook).afterAction(jobId, this.createJob.selector, "");
    }
    function createJobBatch(JobParams[] calldata params) external whenNotPaused returns (uint256[] memory jobIds) {
        jobIds = new uint256[](params.length);
        for (uint i = 0; i < params.length; i++) {
            jobIds[i] = this.createJob(params[i].provider, params[i].evaluators, params[i].requiredApprovals, params[i].expiredAt, params[i].description, params[i].hook);
        }
    }
    function setProvider(uint256 jobId, address provider) external whenNotPaused onlyClient(jobId) inState(jobId, JobState.Open) {
        require(provider != address(0), "Invalid provider");
        jobs[jobId].provider = provider;
    }
    function setBudget(uint256 jobId, uint256 amount) external whenNotPaused inState(jobId, JobState.Open) {
        Job storage job = jobs[jobId];
        require(msg.sender == job.client || msg.sender == job.provider, "Only client or provider");
        require(amount > 0, "Invalid amount");
        job.budget = amount;
        emit BudgetSet(jobId, amount);
    }
    function fund(uint256 jobId, uint256 expectedBudget) external whenNotPaused onlyClient(jobId) inState(jobId, JobState.Open) {
        Job storage job = jobs[jobId];
        require(job.provider != address(0), "Provider not set");
        require(job.budget == expectedBudget, "Budget mismatch");
        require(job.budget > 0, "Budget not set");
        require(usdc.transferFrom(msg.sender, address(this), job.budget), "USDC transfer failed");
        job.state = JobState.Funded;
        emit JobFunded(jobId, msg.sender, job.budget);
    }
    function submit(uint256 jobId, bytes32 deliverable) external whenNotPaused onlyProvider(jobId) inState(jobId, JobState.Funded) {
        Job storage job = jobs[jobId];
        require(deliverable != bytes32(0), "Invalid deliverable");
        require(block.timestamp < job.expiredAt, "Job expired");
        job.deliverable = deliverable;
        job.state = JobState.Submitted;
        emit JobSubmitted(jobId, msg.sender, deliverable);
    }
    function approve(uint256 jobId, bytes32 reason) external whenNotPaused onlyEvaluator(jobId) inState(jobId, JobState.Submitted) {
        Job storage job = jobs[jobId];
        require(!job.hasVoted[msg.sender], "Already voted");
        job.hasVoted[msg.sender] = true;
        job.currentApprovals++;
        emit EvaluatorVoted(jobId, msg.sender, true);
        if (job.currentApprovals >= job.requiredApprovals) _completeJob(jobId);
    }
    function _completeJob(uint256 jobId) internal {
        Job storage job = jobs[jobId];
        job.state = JobState.Completed;
        uint256 platformFee = (job.budget * platformFeeBps) / 10000;
        uint256 providerAmount = job.budget - platformFee;
        require(usdc.transfer(job.provider, providerAmount), "Provider payment failed");
        if (platformFee > 0) { require(usdc.transfer(feeCollector, platformFee), "Fee transfer failed"); totalFeesCollected += platformFee; }
        emit JobCompleted(jobId, providerAmount, platformFee);
        emit PaymentReleased(jobId, job.provider, providerAmount);
    }
    function reject(uint256 jobId, bytes32 reason) external whenNotPaused {
        Job storage job = jobs[jobId];
        if (job.state == JobState.Open) { require(msg.sender == job.client, "Only client can reject Open"); }
        else if (job.state == JobState.Funded || job.state == JobState.Submitted) {
            bool isEvaluator = false;
            for (uint i = 0; i < job.evaluators.length; i++) { if (job.evaluators[i] == msg.sender) { isEvaluator = true; break; } }
            require(isEvaluator, "Only evaluator can reject");
        } else { revert("Cannot reject in this state"); }
        JobState oldState = job.state;
        job.state = JobState.Rejected;
        if (job.budget > 0 && (oldState == JobState.Funded || oldState == JobState.Submitted)) {
            require(usdc.transfer(job.client, job.budget), "Refund failed");
            emit Refunded(jobId, job.client, job.budget);
        }
        emit JobRejected(jobId, msg.sender, reason);
    }
    function claimRefund(uint256 jobId) external {
        Job storage job = jobs[jobId];
        require(job.state == JobState.Funded || job.state == JobState.Submitted, "Job not refundable");
        require(block.timestamp >= job.expiredAt, "Job not expired");
        job.state = JobState.Expired;
        require(usdc.transfer(job.client, job.budget), "Refund failed");
        emit JobExpired(jobId);
        emit Refunded(jobId, job.client, job.budget);
    }
    function getJob(uint256 jobId) external view returns (uint256 id, address client, address provider, address[] memory evaluators, uint256 requiredApprovals, uint256 currentApprovals, uint256 budget, uint256 expiredAt, string memory description, bytes32 deliverable, JobState state, uint256 createdAt, address hook) {
        Job storage job = jobs[jobId];
        return (job.id, job.client, job.provider, job.evaluators, job.requiredApprovals, job.currentApprovals, job.budget, job.expiredAt, job.description, job.deliverable, job.state, job.createdAt, job.hook);
    }
    function hasEvaluatorVoted(uint256 jobId, address evaluator) external view returns (bool) { return jobs[jobId].hasVoted[evaluator]; }
    function setPlatformFee(uint256 newFeeBps) external onlyOwner { require(newFeeBps <= 1000, "Fee too high"); uint256 oldFee = platformFeeBps; platformFeeBps = newFeeBps; emit PlatformFeeUpdated(oldFee, newFeeBps); }
    function setFeeCollector(address newCollector) external onlyOwner { require(newCollector != address(0), "Invalid collector"); address oldCollector = feeCollector; feeCollector = newCollector; emit FeeCollectorUpdated(oldCollector, newCollector); }
    function pause() external onlyOwner { paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { paused = false; emit Unpaused(msg.sender); }
    function transferOwnership(address newOwner) external onlyOwner { require(newOwner != address(0), "Invalid owner"); owner = newOwner; }
}

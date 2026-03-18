// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AgentRegistry.sol";

/**
 * @title JobMarketplace
 * @notice On-chain job marketplace for AI agents with escrow settlement
 * @dev Implements ERC-8183-inspired job lifecycle: Open → Funded → InProgress → Submitted → Completed
 */
contract JobMarketplace {
    // ──────────────────────────── Types ────────────────────────────
    enum JobStatus {
        Open,           // Job posted, escrow funded
        InProgress,     // Provider accepted, work started
        Submitted,      // Provider submitted work
        Completed,      // Client approved, funds released
        Disputed,       // Under dispute
        Cancelled       // Cancelled, funds refunded
    }

    struct Job {
        uint256 id;
        address client;
        string title;
        string description;
        string[] requiredSkills;
        uint256 budget;         // in wei (BNB)
        JobStatus status;
        uint256 createdAt;
        uint256 completedAt;

        // Provider
        uint256 providerAgentId;
        string resultURI;       // IPFS/Greenfield URI of completed work

        // Applications
        uint256[] applicantAgentIds;

        // Rating
        uint8 rating;
        string review;
    }

    struct Application {
        uint256 agentId;
        string proposalURI;
        uint256 appliedAt;
    }

    // ──────────────────────────── State ────────────────────────────
    AgentRegistry public agentRegistry;
    address public admin;
    uint256 public platformFeeBps = 250; // 2.5%
    uint256 public totalVolume;

    uint256 private _nextJobId = 1;
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => mapping(uint256 => Application)) public jobApplications; // jobId => agentId => Application
    mapping(address => uint256[]) public clientJobs;
    mapping(uint256 => uint256[]) public agentJobs; // agentId => jobIds (as provider)
    uint256[] public allJobIds;

    // ──────────────────────────── Events ────────────────────────────
    event JobCreated(uint256 indexed jobId, address indexed client, string title, uint256 budget);
    event JobApplied(uint256 indexed jobId, uint256 indexed agentId);
    event ApplicationAccepted(uint256 indexed jobId, uint256 indexed agentId);
    event WorkSubmitted(uint256 indexed jobId, string resultURI);
    event WorkApproved(uint256 indexed jobId, uint8 rating, uint256 payout);
    event JobDisputed(uint256 indexed jobId);
    event JobCancelled(uint256 indexed jobId);
    event DisputeResolved(uint256 indexed jobId, bool favorProvider);

    // ──────────────────────────── Modifiers ────────────────────────────
    modifier onlyClient(uint256 jobId) {
        require(jobs[jobId].client == msg.sender, "Not job client");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier jobInStatus(uint256 jobId, JobStatus status) {
        require(jobs[jobId].status == status, "Invalid job status");
        _;
    }

    // ──────────────────────────── Constructor ────────────────────────────
    constructor(address _agentRegistry) {
        require(_agentRegistry != address(0), "Zero address");
        agentRegistry = AgentRegistry(_agentRegistry);
        admin = msg.sender;
    }

    // ──────────────────────────── Job Lifecycle ────────────────────────────

    /// @notice Create a job and fund escrow
    function createJob(
        string calldata title,
        string calldata description,
        string[] calldata requiredSkills
    ) external payable returns (uint256) {
        require(bytes(title).length > 0, "Title required");
        require(msg.value > 0, "Budget required");
        require(requiredSkills.length > 0 && requiredSkills.length <= 10, "Invalid skills");

        uint256 jobId = _nextJobId++;

        Job storage job = jobs[jobId];
        job.id = jobId;
        job.client = msg.sender;
        job.title = title;
        job.description = description;
        for (uint i = 0; i < requiredSkills.length; i++) {
            job.requiredSkills.push(requiredSkills[i]);
        }
        job.budget = msg.value;
        job.status = JobStatus.Open;
        job.createdAt = block.timestamp;

        clientJobs[msg.sender].push(jobId);
        allJobIds.push(jobId);

        emit JobCreated(jobId, msg.sender, title, msg.value);
        return jobId;
    }

    /// @notice Agent applies for a job
    function applyForJob(
        uint256 jobId,
        uint256 agentId,
        string calldata proposalURI
    ) external jobInStatus(jobId, JobStatus.Open) {
        (,address agentOwner,,,,,,,,bool active) = agentRegistry.getAgent(agentId);
        require(agentOwner == msg.sender, "Not agent owner");
        require(active, "Agent not active");
        require(jobApplications[jobId][agentId].appliedAt == 0, "Already applied");

        jobApplications[jobId][agentId] = Application({
            agentId: agentId,
            proposalURI: proposalURI,
            appliedAt: block.timestamp
        });

        jobs[jobId].applicantAgentIds.push(agentId);
        emit JobApplied(jobId, agentId);
    }

    /// @notice Client accepts an agent's application
    function acceptApplication(
        uint256 jobId,
        uint256 agentId
    ) external onlyClient(jobId) jobInStatus(jobId, JobStatus.Open) {
        require(jobApplications[jobId][agentId].appliedAt > 0, "No application");

        Job storage job = jobs[jobId];
        job.providerAgentId = agentId;
        job.status = JobStatus.InProgress;

        agentJobs[agentId].push(jobId);

        emit ApplicationAccepted(jobId, agentId);
    }

    /// @notice Provider submits completed work
    function submitWork(
        uint256 jobId,
        string calldata resultURI
    ) external jobInStatus(jobId, JobStatus.InProgress) {
        Job storage job = jobs[jobId];
        (,address agentOwner,,,,,,,,) = agentRegistry.getAgent(job.providerAgentId);
        require(agentOwner == msg.sender, "Not provider");
        require(bytes(resultURI).length > 0, "Result URI required");

        job.resultURI = resultURI;
        job.status = JobStatus.Submitted;

        emit WorkSubmitted(jobId, resultURI);
    }

    /// @notice Client approves work and releases escrow
    function approveWork(
        uint256 jobId,
        uint8 rating,
        string calldata review
    ) external onlyClient(jobId) jobInStatus(jobId, JobStatus.Submitted) {
        require(rating >= 1 && rating <= 5, "Rating 1-5");

        Job storage job = jobs[jobId];
        job.status = JobStatus.Completed;
        job.completedAt = block.timestamp;
        job.rating = rating;
        job.review = review;

        // Calculate payout
        uint256 fee = (job.budget * platformFeeBps) / 10000;
        uint256 payout = job.budget - fee;

        // Update agent reputation
        agentRegistry.addReputation(job.providerAgentId, jobId, rating, review);

        // Transfer funds to provider
        (,address providerOwner,,,,,,,,) = agentRegistry.getAgent(job.providerAgentId);
        totalVolume += job.budget;

        (bool success,) = payable(providerOwner).call{value: payout}("");
        require(success, "Transfer failed");

        emit WorkApproved(jobId, rating, payout);
    }

    /// @notice Client or provider can dispute
    function disputeJob(uint256 jobId) external {
        Job storage job = jobs[jobId];
        require(
            job.status == JobStatus.InProgress || job.status == JobStatus.Submitted,
            "Cannot dispute"
        );
        (,address agentOwner,,,,,,,,) = agentRegistry.getAgent(job.providerAgentId);
        require(msg.sender == job.client || msg.sender == agentOwner, "Not party");

        job.status = JobStatus.Disputed;
        emit JobDisputed(jobId);
    }

    /// @notice Admin resolves dispute
    function resolveDispute(
        uint256 jobId,
        bool favorProvider
    ) external onlyAdmin jobInStatus(jobId, JobStatus.Disputed) {
        Job storage job = jobs[jobId];
        job.status = JobStatus.Completed;
        job.completedAt = block.timestamp;

        if (favorProvider) {
            uint256 fee = (job.budget * platformFeeBps) / 10000;
            uint256 payout = job.budget - fee;
            (,address providerOwner,,,,,,,,) = agentRegistry.getAgent(job.providerAgentId);
            totalVolume += job.budget;
            (bool success,) = payable(providerOwner).call{value: payout}("");
            require(success, "Transfer failed");
        } else {
            (bool success,) = payable(job.client).call{value: job.budget}("");
            require(success, "Refund failed");
        }

        emit DisputeResolved(jobId, favorProvider);
    }

    /// @notice Cancel an open job (no provider yet)
    function cancelJob(uint256 jobId)
        external
        onlyClient(jobId)
        jobInStatus(jobId, JobStatus.Open)
    {
        Job storage job = jobs[jobId];
        job.status = JobStatus.Cancelled;

        (bool success,) = payable(job.client).call{value: job.budget}("");
        require(success, "Refund failed");

        emit JobCancelled(jobId);
    }

    // ──────────────────────────── Views ────────────────────────────
    function getJob(uint256 jobId) external view returns (
        uint256 id,
        address client,
        string memory title,
        string memory description,
        string[] memory requiredSkills,
        uint256 budget,
        JobStatus status,
        uint256 createdAt,
        uint256 providerAgentId,
        string memory resultURI
    ) {
        Job storage j = jobs[jobId];
        return (j.id, j.client, j.title, j.description, j.requiredSkills,
                j.budget, j.status, j.createdAt, j.providerAgentId, j.resultURI);
    }

    function getJobApplicants(uint256 jobId) external view returns (uint256[] memory) {
        return jobs[jobId].applicantAgentIds;
    }

    function getClientJobs(address client) external view returns (uint256[] memory) {
        return clientJobs[client];
    }

    function getAgentJobs(uint256 agentId) external view returns (uint256[] memory) {
        return agentJobs[agentId];
    }

    function getTotalJobs() external view returns (uint256) {
        return allJobIds.length;
    }

    function getAllJobIds() external view returns (uint256[] memory) {
        return allJobIds;
    }

    function getJobRequiredSkills(uint256 jobId) external view returns (string[] memory) {
        return jobs[jobId].requiredSkills;
    }

    // ──────────────────────────── Admin ────────────────────────────
    function setPlatformFee(uint256 newFeeBps) external onlyAdmin {
        require(newFeeBps <= 1000, "Max 10%");
        platformFeeBps = newFeeBps;
    }

    function withdrawFees() external onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees");
        (bool success,) = payable(admin).call{value: balance}("");
        require(success, "Withdraw failed");
    }

    receive() external payable {}
}

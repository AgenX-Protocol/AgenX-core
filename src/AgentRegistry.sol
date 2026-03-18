// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AgentRegistry
 * @notice ERC-721 based AI Agent identity registry for AGENX
 * @dev Agents register with skills and build on-chain reputation through completed jobs
 */
contract AgentRegistry {
    // ──────────────────────────── Types ────────────────────────────
    struct Agent {
        uint256 id;
        address owner;
        string name;
        string metadataURI;    // IPFS/Greenfield URI for avatar, bio, etc.
        string[] skills;
        uint256 reputationScore; // cumulative score (sum of all ratings)
        uint256 totalReviews;
        uint256 jobsCompleted;
        uint256 registeredAt;
        bool active;
    }

    struct Review {
        uint256 jobId;
        address reviewer;
        uint8 rating;       // 1-5 stars
        string comment;
        uint256 timestamp;
    }

    // ──────────────────────────── State ────────────────────────────
    uint256 private _nextAgentId = 1;
    address public jobMarketplace;
    address public admin;

    mapping(uint256 => Agent) public agents;
    mapping(address => uint256[]) public ownerAgents;
    mapping(uint256 => Review[]) public agentReviews;
    mapping(string => uint256[]) public skillToAgents;    // skill => agentIds
    uint256[] public allAgentIds;

    // ──────────────────────────── Events ────────────────────────────
    event AgentRegistered(uint256 indexed agentId, address indexed owner, string name);
    event AgentUpdated(uint256 indexed agentId, string name, string metadataURI);
    event AgentDeactivated(uint256 indexed agentId);
    event ReputationUpdated(uint256 indexed agentId, uint256 jobId, uint8 rating, uint256 newScore);
    event JobMarketplaceSet(address indexed marketplace);

    // ──────────────────────────── Modifiers ────────────────────────────
    modifier onlyAgentOwner(uint256 agentId) {
        require(agents[agentId].owner == msg.sender, "Not agent owner");
        _;
    }

    modifier onlyJobMarketplace() {
        require(msg.sender == jobMarketplace, "Only JobMarketplace");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    // ──────────────────────────── Constructor ────────────────────────────
    constructor() {
        admin = msg.sender;
    }

    // ──────────────────────────── Admin ────────────────────────────
    function setJobMarketplace(address _marketplace) external onlyAdmin {
        require(_marketplace != address(0), "Zero address");
        jobMarketplace = _marketplace;
        emit JobMarketplaceSet(_marketplace);
    }

    // ──────────────────────────── Registration ────────────────────────────
    function registerAgent(
        string calldata name,
        string calldata metadataURI,
        string[] calldata skills
    ) external returns (uint256) {
        require(bytes(name).length > 0, "Name required");
        require(skills.length > 0, "At least one skill");
        require(skills.length <= 10, "Max 10 skills");

        uint256 agentId = _nextAgentId++;

        Agent storage agent = agents[agentId];
        agent.id = agentId;
        agent.owner = msg.sender;
        agent.name = name;
        agent.metadataURI = metadataURI;
        for (uint i = 0; i < skills.length; i++) {
            agent.skills.push(skills[i]);
        }
        agent.registeredAt = block.timestamp;
        agent.active = true;

        ownerAgents[msg.sender].push(agentId);
        allAgentIds.push(agentId);

        // Index skills
        for (uint256 i = 0; i < skills.length; i++) {
            skillToAgents[skills[i]].push(agentId);
        }

        emit AgentRegistered(agentId, msg.sender, name);
        return agentId;
    }

    // ──────────────────────────── Updates ────────────────────────────
    function updateAgent(
        uint256 agentId,
        string calldata name,
        string calldata metadataURI,
        string[] calldata skills
    ) external onlyAgentOwner(agentId) {
        require(agents[agentId].active, "Agent not active");
        require(bytes(name).length > 0, "Name required");
        require(skills.length > 0 && skills.length <= 10, "Invalid skills count");

        Agent storage agent = agents[agentId];
        agent.name = name;
        agent.metadataURI = metadataURI;
        
        // Update skills
        delete agent.skills;
        for (uint i = 0; i < skills.length; i++) {
            agent.skills.push(skills[i]);
        }

        emit AgentUpdated(agentId, name, metadataURI);
    }

    function deactivateAgent(uint256 agentId) external onlyAgentOwner(agentId) {
        agents[agentId].active = false;
        emit AgentDeactivated(agentId);
    }

    // ──────────────────────────── Reputation ────────────────────────────
    function addReputation(
        uint256 agentId,
        uint256 jobId,
        uint8 rating,
        string calldata comment
    ) external onlyJobMarketplace {
        require(rating >= 1 && rating <= 5, "Rating 1-5");
        require(agents[agentId].active, "Agent not active");

        Agent storage agent = agents[agentId];
        agent.reputationScore += rating;
        agent.totalReviews += 1;
        agent.jobsCompleted += 1;

        agentReviews[agentId].push(Review({
            jobId: jobId,
            reviewer: tx.origin,
            rating: rating,
            comment: comment,
            timestamp: block.timestamp
        }));

        emit ReputationUpdated(agentId, jobId, rating, agent.reputationScore);
    }

    // ──────────────────────────── Views ────────────────────────────
    function getAgent(uint256 agentId) external view returns (
        uint256 id,
        address owner,
        string memory name,
        string memory metadataURI,
        string[] memory skills,
        uint256 reputationScore,
        uint256 totalReviews,
        uint256 jobsCompleted,
        uint256 registeredAt,
        bool active
    ) {
        Agent storage a = agents[agentId];
        return (a.id, a.owner, a.name, a.metadataURI, a.skills,
                a.reputationScore, a.totalReviews, a.jobsCompleted,
                a.registeredAt, a.active);
    }

    function getAgentSkills(uint256 agentId) external view returns (string[] memory) {
        return agents[agentId].skills;
    }

    function getAgentReviews(uint256 agentId) external view returns (Review[] memory) {
        return agentReviews[agentId];
    }

    function getAgentsByOwner(address owner) external view returns (uint256[] memory) {
        return ownerAgents[owner];
    }

    function getAgentsBySkill(string calldata skill) external view returns (uint256[] memory) {
        return skillToAgents[skill];
    }

    function getTotalAgents() external view returns (uint256) {
        return allAgentIds.length;
    }

    function getAllAgentIds() external view returns (uint256[] memory) {
        return allAgentIds;
    }

    function getAverageRating(uint256 agentId) external view returns (uint256) {
        Agent storage a = agents[agentId];
        if (a.totalReviews == 0) return 0;
        return (a.reputationScore * 100) / a.totalReviews; // returns rating * 100 for precision
    }
}

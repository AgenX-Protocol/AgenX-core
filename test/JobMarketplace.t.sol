// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {JobMarketplace} from "../src/JobMarketplace.sol";

contract JobMarketplaceTest is Test {
    AgentRegistry public registry;
    JobMarketplace public marketplace;
    
    address public client1 = address(0x1111);
    address public provider1 = address(0x2222);
    address public provider2 = address(0x3333);

    uint256 public agent1Id;
    uint256 public agent2Id;

    function setUp() public {
        vm.deal(client1, 100 ether);
        
        registry = new AgentRegistry();
        marketplace = new JobMarketplace(address(registry));
        registry.setJobMarketplace(address(marketplace));
        
        // Setup initial agents
        string[] memory skills = new string[](1);
        skills[0] = "Solidity";
        
        vm.prank(provider1);
        agent1Id = registry.registerAgent("Agent 1", "uri1", skills);
        
        vm.prank(provider2);
        agent2Id = registry.registerAgent("Agent 2", "uri2", skills);
    }

    // Standard Success Path
    function test_FullJobLifecycle() public {
        string[] memory requiredSkills = new string[](1);
        requiredSkills[0] = "Solidity";
        
        // 1. Create Job
        vm.prank(client1);
        uint256 jobId = marketplace.createJob{value: 1 ether}("Build DEX", "Needs AMM", requiredSkills);
        assertEq(jobId, 1);
        
        // 2. Apply for Job
        vm.prank(provider1);
        marketplace.applyForJob(jobId, agent1Id, "ipfs://proposal1");
        
        // 3. Accept Application
        vm.prank(client1);
        marketplace.acceptApplication(jobId, agent1Id);
        
        // 4. Submit Work
        vm.prank(provider1);
        marketplace.submitWork(jobId, "ipfs://dexcode");
        
        // 5. Approve Work
        uint256 providerBalBefore = provider1.balance;
        vm.prank(client1);
        marketplace.approveWork(jobId, 5, "Great");
        
        assertEq(provider1.balance, providerBalBefore + 0.975 ether);
        
        (, , , , , , JobMarketplace.JobStatus status, , , ) = marketplace.getJob(jobId);
        assertEq(uint(status), uint(JobMarketplace.JobStatus.Completed));
        
        (, , , , , uint256 rep, , uint256 jobsComp, , ) = registry.getAgent(agent1Id);
        assertEq(jobsComp, 1);
        assertEq(rep, 5);
    }

    // Fuzz Testing
    function testFuzz_CreateJobBudget(uint256 budget) public {
        // Assume random budget within human bounds to prevent out of gas due to massive eth counts locally
        vm.assume(budget > 0 && budget < 100_000 ether);
        vm.deal(client1, budget);
        
        string[] memory reqSkills = new string[](1);
        reqSkills[0] = "Dev";
        
        vm.prank(client1);
        uint256 jobId = marketplace.createJob{value: budget}("Title", "Desc", reqSkills);
        
        (, , , , , uint256 returnedBudget, , , , ) = marketplace.getJob(jobId);
        assertEq(returnedBudget, budget);
        assertEq(address(marketplace).balance, budget); // Escrow locked
    }
    
    // Fuzz Testing unauthorized acts
    function testFuzz_UnauthorizedAcceptance(address randomCaller) public {
        vm.assume(randomCaller != client1);
        
        // Client create
        string[] memory reqSkills = new string[](1);
        reqSkills[0] = "Dev";
        vm.prank(client1);
        uint256 jobId = marketplace.createJob{value: 0.5 ether}("T", "D", reqSkills);
        
        // Provider applies
        vm.prank(provider1);
        marketplace.applyForJob(jobId, agent1Id, "ipfs://proposal");
        
        // Unauthorized tries to accept
        vm.prank(randomCaller);
        vm.expectRevert("Not job client");
        marketplace.acceptApplication(jobId, agent1Id);
    }
    
    // Test Edge Case: Rating Out of Bounds
    function test_RatingOutOfBounds() public {
        string[] memory reqSkills = new string[](1);
        reqSkills[0] = "Dev";
        vm.prank(client1);
        uint256 jobId = marketplace.createJob{value: 0.1 ether}("T", "D", reqSkills);
        
        vm.prank(provider1);
        marketplace.applyForJob(jobId, agent1Id, "ipfs://proposal");
        
        vm.prank(client1);
        marketplace.acceptApplication(jobId, agent1Id);
        
        vm.prank(provider1);
        marketplace.submitWork(jobId, "uri");
        
        vm.startPrank(client1);
        vm.expectRevert("Rating 1-5");
        marketplace.approveWork(jobId, 6, "Review");
        
        vm.expectRevert("Rating 1-5");
        marketplace.approveWork(jobId, 0, "Review");
        vm.stopPrank();
    }
}

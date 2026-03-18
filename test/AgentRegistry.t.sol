// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public registry;
    address public client1 = address(0x1111);
    address public provider1 = address(0x2222);
    address public marketplaceMock = address(this); // Mock this test contract as the marketplace

    function setUp() public {
        registry = new AgentRegistry();
        // Authorize this test contract to act as the JobMarketplace wrapper to update reputation
        registry.setJobMarketplace(marketplaceMock);
    }

    // Basic register
    function test_RegisterAgent() public {
        vm.startPrank(provider1);
        string[] memory skills = new string[](2);
        skills[0] = "Solidity";
        skills[1] = "Next.js";
        
        uint256 id = registry.registerAgent("Test Agent", "ipfs://Qmdummy", skills);
        assertEq(id, 1);
        
        (, address owner, string memory returnedName, , , , , , , bool active) = registry.getAgent(id);
        assertEq(owner, provider1);
        assertEq(returnedName, "Test Agent");
        assertEq(active, true);
        vm.stopPrank();
    }

    // Fuzz Testing
    function testFuzz_RegisterAgent(
        string memory name, 
        string memory metadataURI, 
        string[] memory skills,
        address randomProvider
    ) public {
        // Assume provider is not address zero
        vm.assume(randomProvider != address(0));
        vm.assume(bytes(name).length > 0);
        // We limit skills array size to match contract max
        vm.assume(skills.length > 0 && skills.length <= 10);

        vm.startPrank(randomProvider);
        uint256 id = registry.registerAgent(name, metadataURI, skills);
        
        (, address owner, string memory returnedName, string memory returnedURI, string[] memory returnedSkills, , , , , ) = registry.getAgent(id);
        
        assertEq(owner, randomProvider);
        assertEq(returnedName, name);
        assertEq(returnedURI, metadataURI);
        assertEq(returnedSkills.length, skills.length);
        
        if(skills.length > 0) {
            uint256[] memory agentsWithSkill = registry.getAgentsBySkill(skills[0]);
            bool found = false;
            for(uint i = 0; i < agentsWithSkill.length; i++) {
                if(agentsWithSkill[i] == id) found = true;
            }
            assertTrue(found, "Agent not indexed by first skill");
        }
        vm.stopPrank();
    }

    // Fuzz Update Reputation
    function testFuzz_UpdateReputation(uint8 score, string memory review) public {
        // Constrain score to max 5 (the contract should revert if > 5)
        
        // Setup an agent first
        vm.startPrank(provider1);
        string[] memory skills = new string[](1);
        skills[0] = "Auditing";
        uint256 agentId = registry.registerAgent("AuditBot", "uri", skills);
        vm.stopPrank();

        if (score > 5) {
            vm.expectRevert("Rating 1-5");
            registry.addReputation(agentId, 999, score, review);
        } else if (score == 0) {
            vm.expectRevert("Rating 1-5");
            registry.addReputation(agentId, 999, score, review);
        } else {
            // Act as marketplace
            registry.addReputation(agentId, 999, score, review);
            (, , , , , uint256 rep, uint256 reviews, uint256 jobsComp, , ) = registry.getAgent(agentId);
            assertEq(reviews, 1);
            assertEq(rep, score);
            assertEq(jobsComp, 1);
        }
    }

    // Fuzz Security: Unauthorized Reputation Update
    function testFuzz_UnauthorizedReputation(address attacker) public {
        vm.assume(attacker != marketplaceMock);

        // Setup an agent
        vm.startPrank(provider1);
        string[] memory skills = new string[](1);
        skills[0] = "Skill";
        uint256 agentId = registry.registerAgent("Alice", "uri", skills);
        vm.stopPrank();

        vm.startPrank(attacker);
        vm.expectRevert("Only JobMarketplace");
        registry.addReputation(agentId, 999, 5, "Great!");
        vm.stopPrank();
    }
}

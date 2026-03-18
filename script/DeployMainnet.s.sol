// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {JobMarketplace} from "../src/JobMarketplace.sol";

/**
 * @title DeployMainnet
 * @notice Production deployment script for BNB Chain Mainnet
 * @dev Run with: forge script script/DeployMainnet.s.sol --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployMainnet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("=== AGENX Production Deployment ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy AgentRegistry (ERC-8004 Identity Layer)
        AgentRegistry registry = new AgentRegistry();
        console.log("AgentRegistry deployed at:", address(registry));

        // 2. Deploy JobMarketplace (ERC-8183 Escrow Layer)
        JobMarketplace marketplace = new JobMarketplace(address(registry));
        console.log("JobMarketplace deployed at:", address(marketplace));

        // 3. Authorize the Marketplace to update agent reputations
        registry.setJobMarketplace(address(marketplace));
        console.log("JobMarketplace authorized on AgentRegistry");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("VITE_AGENT_REGISTRY_ADDRESS=", address(registry));
        console.log("VITE_JOB_MARKETPLACE_ADDRESS=", address(marketplace));
        console.log("");
        console.log("Next Steps:");
        console.log("1. Update frontend .env with the above addresses");
        console.log("2. Verify contracts: forge verify-contract <address> AgentRegistry --chain-id 56");
        console.log("3. Update RPC URL in Web3Context.jsx and Home.jsx to mainnet");
    }
}

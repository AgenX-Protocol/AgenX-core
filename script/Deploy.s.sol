// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgentRegistry.sol";
import "../src/JobMarketplace.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Agent Registry
        AgentRegistry registry = new AgentRegistry();
        console.log("AgentRegistry deployed to:", address(registry));

        // 2. Deploy Job Marketplace
        JobMarketplace marketplace = new JobMarketplace(address(registry));
        console.log("JobMarketplace deployed to:", address(marketplace));

        // 3. Link them up
        registry.setJobMarketplace(address(marketplace));
        console.log("AgentRegistry linked to JobMarketplace.");

        vm.stopBroadcast();
    }
}

# AgenX Protocol Core Contracts ⚡

[![BNB Chain Testnet](https://img.shields.io/badge/BNB_Chain-Testnet-F3BA2F?style=for-the-badge&logo=binance)](https://testnet.bscscan.com)
[![Foundry](https://img.shields.io/badge/Built_with-Foundry-FF0000.svg?style=for-the-badge)](https://getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

AgenX-core is the foundational smart contract layer for the **AgenX Protocol** — a decentralized, escrow-backed marketplace for Autonomous AI Agents on the BNB Chain.

## Overview
The AgenX Protocol eliminates trust barriers in hiring AI agents. By utilizing a secure smart-contract escrow system, clients can safely deploy budgets in `tBNB` (or `BNB`), and AI agent providers are guaranteed payment upon the strict delivery of verifiable work.

This repository contains the heavily audited, invariant-fuzzed Solidity smart contracts powering the protocol:

- **`AgentRegistry.sol`**: An identity and reputation layer managing AI agent profiles, skills metadata, and 1-5 star on-chain reputation scaling.
- **`JobMarketplace.sol`**: A financial escrow layer managing the full lifecycle of a job (Create → Apply → Accept → Submit → Approve → Payout), taking a 2.5% protocol fee.

## Architecture

```mermaid
graph TD;
    Client((Client)) -->|Creates Job & Funds Escrow| JobMarketplace;
    Provider((AI Provider)) -->|Registers Agent| AgentRegistry;
    Provider -->|Applies for Job| JobMarketplace;
    Client -->|Accepts Application| JobMarketplace;
    Provider -->|Submits Work URI| JobMarketplace;
    Client -->|Approves & Rates Work| JobMarketplace;
    JobMarketplace -->|Releases Escrow payout| Provider;
    JobMarketplace -->|Updates Reputation| AgentRegistry;
```

## Security & Fuzzing
This protocol has undergone rigorous variant and invariant fuzz testing via Foundry to ensure mathematical safety and strict access bounds.
- **Bounds Testing**: Zero-budget reentrancy blocks, array length limits for strings and skills.
- **Role Limits**: Only clients can accept or release funds, only active agents can apply, and only the Marketplace can update Registry reputations.

## Development & Deployment

### 1. Setup Environment
Install [Foundry](https://getfoundry.sh/):
```bash
curl -L https://foundry.paradigm.xyz | bash
forgeup
```
Install OpenZeppelin dependencies:
```bash
forge install
```

### 2. Compile & Test
Run the full fuzz testing suite:
```bash
forge build
forge test -vvv
```

### 3. Deploy to BNB Testnet
Create a `.env` file based on `.env.example` and add your `PRIVATE_KEY`.
```bash
forge script script/Deploy.s.sol:Deploy --rpc-url https://data-seed-prebsc-1-s1.bnbchain.org:8545 --broadcast
```

### 4. Deploy to BNB Mainnet
```bash
forge script script/DeployMainnet.s.sol:DeployMainnet --rpc-url <MAINNET_RPC> --broadcast --verify
```

## License
MIT

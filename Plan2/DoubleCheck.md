Hybrid Snapshot v1 & Native Discourse Governance Architecture
This document provides the complete architectural blueprint, dependency mapping, and multi-phase execution plan for deploying a native off-chain token voting engine inside Discourse. By combining Society Protocol's custom infrastructure with Snapshot's open-source cryptographic libraries (Snapshot v1 paradigm), organizations achieve full governance autonomy without third-party SaaS fees ($6,000/yr) or heavy microservice maintenance.

1. Executive Architectural Overview
   Snapshot v1 operates as an off-chain signaling layer: proposals are created, users sign EIP-712 messages off-chain, and token balances are evaluated against a historical EVM block height. Instead of running Snapshot's heavy server cluster (Snapshot Hub, Sequencer, Checkpoint, and Mana), this architecture embeds the Snapshot v1 lifecycle natively inside the discourse-siwe-auth Discourse plugin.
   Key Principle: Use @snapshot-labs/snapshot.js for standard EIP-712 payload generation and signature verification inside your existing ui/ module (Vite + Wagmi + Viem), while storing payloads in the Discourse Rails database and resolving ERC-1155 identity weights via web3-app-subgraph.
2. Repository & Dependency Inventory
   Society Protocol Core Repositories
   Repository Name
   Link
   Functional Role in Governance Stack

discourse-siwe-auth
https://github.com/SocietyProtocol/discourse-siwe-auth
Discourse plugin host. Manages SIWE sessions, sp_proposals / sp_votes database tables, Shielded Voting logic, and Ember UI widgets.
web3-app-contracts
https://github.com/SocietyProtocol/web3-app-contracts
Smart contracts managing ERC-1155 identity badges (SP DAO #11, Governor #13, Core Team #25, Contributor #26, Moderator #28).
web3-app-subgraph
https://github.com/SocietyProtocol/web3-app-subgraph
GraphQL indexer querying historical ERC-1155 token/badge holdings at exact EVM block numbers.
web3-app-client
https://github.com/SocietyProtocol/web3-app-client
Frontend Web3 client library embedded inside the plugin's ui/ directory as a compiled bundle (siwe.iife.js).

Snapshot Labs Open-Source Dependencies & Reference Repos
Package / Repository
Link
Usage & Integration Strategy

@snapshot-labs/snapshot.js
https://www.npmjs.com/package/@snapshot-labs/snapshot.js
Primary NPM Dependency: Installed in ui/package.json. Generates EIP-712 domains, formats vote payloads, and recovers signers.
snapshot-labs/snapshot-v1
https://github.com/snapshot-labs/snapshot-v1
Reference Repo: Classic Snapshot Web UI. Used for UI layout reference and proposal state management.
snapshot-labs/snapshot-hub
https://github.com/snapshot-labs/snapshot-hub
Reference Repo: Node.js backend receiving vote payloads. Replaced entirely by DiscourseSiwe::VotingController in Rails.
snapshot-labs/snapshot-strategies
https://github.com/snapshot-labs/snapshot-strategies
Algorithm Reference: Source code for 400+ voting weight formulas (Quadratic, Split/Weighted, Approval, Ranked-Choice).
snapshot-labs/sx-monorepo
https://github.com/snapshot-labs/sx-monorepo
Reference Repo: Modern monorepo containing on-chain Snapshot X and Governor execution schemas.

3. System Architecture & Data Sequence
   ┌────────────────────────────────────────────────────────────────────────┐
   │ DISCOURSE FORUM ENVIRONMENT │
   │ │
   │ ┌───────────────────────┐ ┌────────────────────────┐ │
   │ │ Discourse Ember UI │ │ discourse-siwe-auth │ │
   │ │ (sp-vote-widget.hbs) │ │ (Rails Database & Hub) │ │
   │ └───────────┬───────────┘ └───────────▲────────────┘ │
   │ │ │ │
   │ ▼ 1. User Choice │ 3. POST │
   │ ┌───────────────────────┐ │ Signed │
   │ │ ui/ (Wagmi + Viem) ├───────────────────────────┘ Payload │
   │ │ @snapshot-labs/ │ │
   │ │ snapshot.js │ 2. EIP-712 Signature │
   │ └───────────┬───────────┘ (MetaMask / WalletConnect) │
   └───────────────┼────────────────────────────────────────────────────────┘
   │
   ▼ 4. Query ERC-1155 Badges at Snapshot Block Height
   ┌─────────────────────┐
   │ web3-app-subgraph │ (Historical Balance Query)
   └─────────────────────┘

4. Detailed 4-Phase Implementation Roadmap
   Phase 1: Standardized EIP-712 Signing Engine
   Task 1.1: Dependency Installation: Install @snapshot-labs/snapshot.js inside ui/package.json.
   Task 1.2: Signature Export: Implement Client712 inside ui/src/main.ts and export window.SiweAuth.signVotePayload({ topicId, choice }).
   Task 1.3: Rails Signature Verification: In app/controllers/discourse_siwe/voting_controller.rb, verify that the recovered EIP-712 signer address matches current_user.custom_fields['wallet_address'].
   Phase 2: Historical Snapshot & Subgraph Weighting Engine
   Task 2.1: Block Number Capture: When an admin or staff member publishes a proposal topic, automatically query Ethereum RPC (DiscourseSiwe::EthRpc.eth_block_number) and save the current block number into sp_proposals.snapshot_block.
   Task 2.2: Subgraph Balance Resolution: When a vote payload is received, query web3-app-subgraph using GraphQL at the recorded snapshot_block height for the voter's ERC-1155 token balances.
   Task 2.3: Strategy Weight Calculation: Calculate voter weight using sp_proposals.strategy_rules (e.g., Badge #11 = 1 vote, Badge #13 = 5 votes).
   Phase 3: Shielded Voting (Secret Ballots) & Lifecycle Automation
   Task 3.1: Active Proposal Masking: While Time.now.utc < proposal.ends_at and status is open, ensure API responses scrub choice totals and individual vote allocations (returning voting_power: nil).
   Task 3.2: Automated Unmasking: Upon reaching ends_at or manual proposal closure, automatically unmask raw choice counts and calculate winning tallies.
   Task 3.3: Discourse Thread Summary Bot: Run a background job (Sidekiq) that posts an automated, formatted summary reply to the Discourse proposal topic displaying final certified results.
   Phase 4: Advanced Tallies & Execution Payloads
   Task 4.1: Advanced Voting Algorithms: Add support for Split/Weighted Voting and Quadratic Voting by adapting mathematical formulas from snapshot-labs/snapshot-strategies into sp_proposal.rb.
   Task 4.2: On-Chain Safe Payloads: Store target contract calls inside sp_proposals.execution_payload.
   Task 4.3: Multisig Execution: Generate formatted Safe transaction payloads from passed proposals for execution via web3-app-contracts.
5. Local Development & Testing Instructions

# 1. Switch to feature branch inside plugin directory

cd ~/Developer/Pluggin\ SPxDiscourse/discourse-siwe-auth
git checkout -b feature/native-token-voting

# 2. Install snapshot.js and compile Vite frontend bundle

cd ui
pnpm add @snapshot-labs/snapshot.js
pnpm build
cd ..

# 3. Run database migrations inside local Discourse container

cd ~/discourse
bin/rake db:migrate

# 4. Run automated test suite

cd ~/Developer/Pluggin\ SPxDiscourse/discourse-siwe-auth
bundle exec rspec test/voting_unit_test.rb

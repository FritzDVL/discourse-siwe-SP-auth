# Society Protocol Web3 Outpost Suite: Native Token Governance & Voting Architecture

**Document Version:** 3.0 (Unified Architecture)  
**Date:** September 22, 2026  
**Target Repository:** `SocietyProtocol/discourse-siwe-auth` (Evolving into Unified Web3 Outpost Suite)  
**Target Branch:** `feature/native-token-voting`  

---

## 1. Strategic Architectural Vision: The Unified Outpost Suite

Originally conceived as a standalone Sign-In with Ethereum (SIWE) plugin, this project has evolved into a comprehensive **Web3 Outpost Suite for Discourse**. Instead of fracturing functionality across multiple fragile plugins with conflicting Web3 frontend libraries, the system is architected as a **single, cohesive, modular plugin suite** where forum administrators toggle features independently via Discourse Site Settings:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   SOCIETY PROTOCOL WEB3 OUTPOST SUITE                  │
├─────────────────┬──────────────────────┬───────────────────────────────┤
│ 1. SIWE Auth    │ 2. Outpost Identity  │ 3. Token Gating & Governance  │
│ • EOA Wallets   │ • ERC-1155 Badges    │ • Auto Group Sync             │
│ • Safe (1271)   │ • Subgraph Profiles  │ • Snapshot v1 Token Voting    │
│ • EIP-6492      │ • Custom Avatars/Bio │ • Weighted / Quadratic Tallies│
└─────────────────┴──────────────────────┴───────────────────────────────┘
```

### Modular Site Settings Structure
* `siwe_enabled`: Core Sign-In with Ethereum authentication.
* `siwe_identity_resolution_mode`: Outpost profile & badge sync via Subgraph / RPC.
* `siwe_token_gating_enabled`: Automatic group membership sync based on held badges.
* `siwe_voting_enabled`: Native off-chain EIP-712 token voting.
* `siwe_voting_chain_id`: EVM Chain ID for governance hashing (default: `1`).
* `siwe_voting_shielded_default`: Default secret-ballot setting for new proposals.

---

## 2. Groundwork Already Completed & Verified

The groundwork laid in commits `2cff378` and `a24aa0d` on `feature/native-token-voting` has already validated core components:

1. **Lightweight Modern Web3 Toolchain:**
   * Uses `@wagmi/core` and `viem` inside `ui/src/main.ts` for EIP-712 typed signing without bundle bloat.
   * Avoids heavy legacy dependencies from `@snapshot-labs/snapshot.js`.
2. **Dual-Tier EIP-712 Verification:**
   * `lib/discourse_siwe/eip712.rb` verifies signatures for standard EOA wallets (via `Eth::Signature`) and smart contract wallets (Safe / EIP-1271 / EIP-6492 bytecode validation).
3. **Historical Block Resolution:**
   * `EthRpc.eth_block_number` captures EVM block heights.
   * `IdentityResolver.resolve_badges_at_block` queries `web3-app-subgraph` at exact block numbers with RPC fallback.
4. **Initial Shielded Voting:**
   * `SpProposal#tally_results` scrubs choice totals while a proposal is active and marked shielded.
5. **Passing Unit Tests:**
   * [test/voting_unit_test.rb](file:///Users/user/Developer/Pluggin%20SPxDiscourse/discourse-siwe-auth/test/voting_unit_test.rb) (12 runs, 31 assertions, 0 failures).

---

## 3. Four Core Refinements for Native Governance

### Refinement 1: Staff Proposal Creator UI (In-Forum Management)
* **Goal:** Eliminate manual `curl` / API requests to create proposals.
* **Architecture:**
  * Add a "Create Governance Proposal" action in Discourse for staff/admins:
    * Accessible directly on topics tagged `#governance` or via a modal/topic action.
    * Form inputs: Title, Voting Options (dynamic list), Duration / End Date, Voting Type (Single Choice, Weighted, Quadratic, Approval), Shielded toggle.
  * Backend endpoint `POST /sp-voting/proposal`:
    * Automatically fetches `DiscourseSiwe::EthRpc.eth_block_number` to freeze badge snapshot height.
    * Validates permissions (`current_user.staff?`).
    * Persists `sp_proposals` record attached to `topic_id`.

### Refinement 2: Advanced Voting Types (Weighted Voting First)
To power hackathons, grant allocations, and community competitions, the voting engine supports multiple tally models:

1. **Single Choice (Standard):**
   * Voter selects exactly one option index.
   * 100% of voting power applied to selected choice.
2. **Weighted Voting (Priority for Competitions):**
   * Voter allocates their voting power across multiple options (e.g. 50% to Project A, 30% to Project B, 20% to Project C).
   * Payload stores percentage distribution: `{ "0": 50, "1": 30, "2": 20 }`.
   * Tally engine calculates proportional voting power per choice.
3. **Quadratic Voting:**
   * Voters allocate voting credits; effective weight per choice scales quadratically: $\text{Weight} = \sqrt{\text{Allocated Power}}$.
   * Mitigates whale dominance in community polls.
4. **Approval Voting:**
   * Voters select any number of acceptable options.
   * 100% of voter's power is added to each selected option.

### Refinement 3: Streamlined Shielded Voting Lifecycle (No Bot Required)
* **Decision:** Omit background Sidekiq reply bots for v1 to keep architecture clean and avoid thread spam.
* **Mechanism:**
  * While `Time.now.utc < proposal.ends_at` and `proposal.status == 'open'`:
    * API returns `tally` with `voting_power: nil`, `vote_count: nil`, `is_shielded: true`.
    * Widget UI displays a secure "Shielded Ballot Active" badge with voter count only.
  * When `Time.now.utc >= proposal.ends_at` or proposal is manually closed:
    * API automatically unmasks all choice distributions and winning percentages.
    * Widget UI renders the full certified results breakdown with percentage bars and badge counts.

### Refinement 4: Safe Multisig Execution Payloads (DAO Governance Path)
* Proposal creators can optionally attach an `execution_payload` (JSONB) specifying target contract calls:
  * `{ "to": "0x...", "value": "0", "data": "0x...", "operation": 0 }`
* When a proposal passes, the widget displays a formatted Safe Transaction payload that DAO signers can copy or load directly into the Safe {Wallet} App or execute via `web3-app-contracts`.

---

## 4. Technical Specifications & Data Models

### Database Migration: `db/migrate/20260922000000_add_advanced_voting_to_sp_proposals.rb`

```ruby
class AddAdvancedVotingToSpProposals < ActiveRecord::Migration[7.0]
  def change
    add_column :sp_proposals, :voting_type, :integer, default: 0, null: false # 0: single_choice, 1: weighted, 2: quadratic, 3: approval
    add_column :sp_proposals, :quorum, :decimal, precision: 30, scale: 0, default: 0
    add_column :sp_proposals, :execution_payload, :jsonb, default: nil
  end
end
```

### EIP-712 Typed Data Specification

```typescript
// Shared EIP-712 Typed Schema (ui/src/main.ts and lib/discourse_siwe/eip712.rb)
export const EIP712_DOMAIN = {
  name: 'Society Protocol Governance',
  version: '1',
  chainId: 1, // Resolves from SiteSetting.siwe_voting_chain_id
}

export const EIP712_TYPES = {
  Vote: [
    { name: 'topicId', type: 'uint256' },
    { name: 'choice', type: 'string' }, // JSON stringified choice: "[0]" or "{\"0\":50,\"1\":50}"
    { name: 'timestamp', type: 'uint256' },
  ],
}
```

*Using a stringified canonical JSON representation for `choice` allows arbitrary voting payloads (single index, array, or weight map) while maintaining deterministic EIP-712 hashing across frontend and backend.*

---

## 5. Phased Implementation Roadmap

### Phase 1: Database & Core Tally Engine
1. Create migration for `voting_type`, `quorum`, and `execution_payload`.
2. Update `lib/discourse_siwe/voting_strategy.rb` with mathematical formulas for:
   - `calculate_weighted_tallies(votes, options_count)`
   - `calculate_quadratic_tallies(votes, options_count)`
   - `calculate_approval_tallies(votes, options_count)`
3. Update `SpProposal#tally_results` to dispatch according to `voting_type`.
4. Update `lib/discourse_siwe/eip712.rb` to support canonical string/array choices.

### Phase 2: Staff Proposal Creator Modal
1. Add Discourse staff modal / action in Ember to create proposals directly from topics.
2. Update `DiscourseSiwe::VotingController#create_proposal` to validate and persist advanced fields.
3. Automatically lock current EVM block height via `EthRpc.eth_block_number`.

### Phase 3: Frontend Vote Widget Enhancements
1. Update `assets/javascripts/discourse/components/sp-vote-widget.js.es6`:
   - Single Choice: Radio option cards.
   - Weighted Voting: Sliders / percentage input fields with total-percentage validation.
   - Approval Voting: Multi-selection checkboxes.
2. Display Safe execution payload button for passed proposals.

### Phase 4: Automated Testing & Verification
1. Extend `test/voting_unit_test.rb`:
   - Test weighted voting distribution math.
   - Test quadratic voting calculations.
   - Test approval voting calculations.
   - Test canonical EIP-712 hashing for stringified choice payloads.

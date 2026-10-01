# Society Protocol Web3 Outpost Suite for Discourse

A comprehensive Web3 forum suite by [Society Protocol](https://societyprotocol.io/) that transforms Discourse into a decentralized community outpost. It combines **Sign-In with Ethereum (SIWE)**, **on-chain identity resolution** (ENS and ERC-1155 profile badges), **badge-based token gating**, and **native off-chain token governance & weighted voting**—with zero external SaaS fees or microservice dependencies.

## What this plugin is

Originally starting from [`signinwithethereum/discourse-siwe-auth`](https://github.com/signinwithethereum/discourse-siwe-auth), Society Protocol has evolved this project into a complete, modular **Web3 Outpost Suite** structured around four pillars:

1. **Web3 Authentication (SIWE):** Gasless wallet sign-in supporting both standard EOA wallets (MetaMask, Rainbow, Coinbase) and smart contract accounts (Safe via EIP-1271, undeployed smart accounts via EIP-6492).
2. **Multi-Identity Resolution & Display Selector:** Resolves ENS domains/avatars and Society Protocol ERC-1155 outpost profile badges from The Graph and RPC. Users can switch their visible forum identity (Wallet, ENS, or Society Outpost) from **Preferences > Profile**.
3. **Badge Token Gating:** Synchronizes held ERC-1155 identity badges with Discourse groups (e.g. Governors, Core Team, Moderators), granting exclusive category permissions and badges automatically.
4. **Native Token Governance & Weighted Voting:** Embeds Snapshot v1 architecture natively inside Discourse. Community members sign off-chain EIP-712 ballots weighted by their historical badge holdings at a frozen EVM block height, with secret-ballot **Shielded Voting**, **Weighted Voting** for competitions, and **Safe Multisig execution payloads**.

What users experience:

- Injected wallets (MetaMask, Safe, etc.) work out of the box.
- WalletConnect / Reown works when a project ID is configured.
- If an Ethereum RPC URL is supplied, the plugin resolves ENS names and avatars
  server-side and suggests the ENS name as the default username for new sign-ups.
- If Society Protocol resolution is enabled, the plugin also resolves the user's
  Society outpost profile and lets the user pick their display identity:
  **wallet**, **ENS**, or **Society Protocol**.

The chosen display identity updates the user's visible name and avatar in
Discourse; the underlying username is never changed by this feature.

> **Fork note.** This repo tracks the fixes we contributed back upstream
> ([signinwithethereum/discourse-siwe-auth#2](https://github.com/signinwithethereum/discourse-siwe-auth/issues/2))
> for installing on current Discourse, which ships Ruby 3.4 inside the official
> `discourse/base` Docker image. See
> [Compatibility notes](#compatibility-notes-discourse--ruby-34) below.

## Requirements

- A Discourse forum that is self-hosted or hosted with a provider that supports
  third-party plugins, like [Communiteq](https://www.communiteq.com/).

## Installation

Access your container's `app.yml` file:

```bash
cd /var/discourse
nano containers/app.yml
```

Add a `before_code` hook to install `rubyzip` and an `after_code` hook to
clone the plugin:

```yml
hooks:
  before_code:
    - exec:
        cmd:
          - gem install rubyzip
  after_code:
    - exec:
      cd: $home/plugins
      cmd:
        - sudo -E -u discourse git clone https://github.com/discourse/docker_manager.git
        - sudo -E -u discourse git clone https://github.com/SocietyProtocol/discourse-siwe-auth.git # <-- added
```

### Why both hooks are needed

**`before_code` → `gem install rubyzip`**: the `rbsecp256k1` native crypto gem
this plugin depends on uses `rubyzip` inside its own `extconf.rb` to fetch and
unpack the libsecp256k1 C source during build. That happens at `bundle install`
time, _before_ Discourse processes the `gem` directives in `plugin.rb`, so the
plugin's own gem block can't supply it in time. Installing `rubyzip`
system-wide in `before_code` guarantees it's on disk when the native
extension's build script runs.

**`after_code` → `sudo -E -u discourse git clone`**: always run the clone as
the unprivileged `discourse` user. On Ubuntu 24.04 a plain `git clone` runs as
`root` inside the container and produces files the Rails build cannot read,
which surfaces as a confusing failure during `./launcher rebuild app`. The
`-E` flag preserves the environment; `-u discourse` runs the command as the
user the rest of the Discourse build expects to own the plugin tree. Match the
exact form of the existing `docker_manager.git` line in your `app.yml`; if
that line is missing the prefix, your container is using an older layout —
add the prefix to both lines rather than dropping it from the new one.

Rebuild the container:

```bash
cd /var/discourse
./launcher rebuild app
```

## Configuration

After installation, find the plugin under **Admin > Plugins** and make sure it
is enabled:

![Installed plugins](/installed-plugins.png 'Installed plugins')

Click **Settings** to configure the plugin:

![Plugin settings](/settings.png 'Plugin settings')

From here you can customize the sign-in statement and optionally add a
WalletConnect / Reown project ID. Without a project ID, only injected wallets
(MetaMask, Safe, etc.) are available.

### Settings

| Setting                           | Description                                                                                                                                                                                                                                                                 |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Discourse siwe enabled**        | Enable or disable Sign-In with Ethereum authentication.                                                                                                                                                                                                                     |
| **Siwe ethereum rpc url**         | _Optional._ An Ethereum JSON-RPC endpoint used for ENS name/avatar resolution and EIP-1271 signature verification (required for smart contract wallets like SAFE). A dedicated provider (Alchemy, Infura) is recommended. Example: `https://mainnet.infura.io/v3/YOUR_KEY`. |
| **Siwe project ID**               | _Optional._ A WalletConnect / Reown project ID. Without it, only injected wallets (MetaMask, Safe, etc.) are available. To enable WalletConnect, create a free project ID at [dashboard.reown.com](https://dashboard.reown.com).                                            |
| **Siwe statement**                | The human-readable statement shown in the SIWE message. Defaults to "Sign in with Ethereum".                                                                                                                                                                                |
| **Siwe society enabled**          | Enable Society Protocol identity resolution and the display-identity toggle.                                                                                                                                                                                                |
| **Siwe society subgraph url**     | _Optional._ The Society Protocol subgraph endpoint. Defaults to the live mainnet endpoint; leave blank to force direct RPC resolution.                                                                                                                                      |
| **Siwe society badges contract**  | Society Protocol Badges (ERC-1155) contract address. Defaults to the current mainnet proxy; update only if the contract is redeployed.                                                                                                                                      |
| **Siwe identity resolution mode** | Preferred resolution mode: `subgraph` (default, falls back to RPC) or `rpc` (direct contract calls only).                                                                                                                                                                   |
| **Siwe society group mapping**    | Token-gating mapping: `badge_id:group_name\|badge_id:group_name`. Example: `13:governors\|25:core-team\|28:moderators`. Leave blank to disable group sync.                                                                                                                  |
| **Siwe voting enabled**           | Enable native token governance, EIP-712 off-chain voting, and topic vote cards.                                                                                                                                                                                             |
| **Siwe voting chain id**          | EVM Chain ID used in EIP-712 governance signature hashing (default: `1` for Ethereum Mainnet).                                                                                                                                                                              |
| **Siwe voting tag**               | Tag applied to topics (default: `governance`) where the governance proposal widget mounts above the posts.                                                                                                                                                                  |
| **Siwe voting shielded default**  | Default secret-ballot setting for newly created proposals (tally hidden until vote closes).                                                                                                                                                                                 |

## Compatibility notes (Discourse + Ruby 3.4)

Recent versions of Discourse ship Ruby 3.4 inside the official
`discourse/base` Docker image and pin `rubyzip` to the 3.x line. That
combination broke the install of upstream
[`signinwithethereum/discourse-siwe-auth`](https://github.com/signinwithethereum/discourse-siwe-auth)
(see issue [#2](https://github.com/signinwithethereum/discourse-siwe-auth/issues/2)).
This fork fixes three distinct issues in `plugin.rb` so that `./launcher
rebuild app` completes cleanly. They are documented here so the changes
make sense to anyone reading the diff.

### 1. Discourse's plugin `gem` DSL needs an explicit version string

Discourse's plugin loader exposes a `gem` DSL whose signature is
`gem(name, version, opts = {})`, and it shells out to
`gem install ... --ignore-dependencies` under the hood. The original
plugin used short forms like `gem 'eth', require: false` (no version
arg). On Ruby 3.x that makes RubyGems treat the keyword-arguments hash
as the `version` argument, producing:

```
ERROR:  While executing gem ... (Gem::Requirement::BadRequirementError)
    Illformed requirement ["{"]
```

Every gem line in `plugin.rb` therefore now carries an explicit version
string as its second positional argument, e.g.
`gem 'eth', '0.5.17', require: false`.

### 2. Every transitive dependency must be declared explicitly

Because Discourse passes `--ignore-dependencies` to `gem install`,
RubyGems will not pull in transitive deps automatically. Two consequences
on Ruby 3.4:

- **`base64` is no longer a default gem** in Ruby 3.4 (it was demoted to
  a bundled gem). `eth >= 0.5.16` is the first version that explicitly
  depends on `base64`, so it must be listed in `plugin.rb`.
- The `eth` / `siwe` gems also need their full subgraph listed in
  install order: `ecdsa`, `h2c`, `bls12-381`, `http-2`, `httpx`. Same
  reasoning applies to lower-level build deps (`pkg-config`,
  `mini_portile2`, `ffi`, `ffi-compiler`, `konstructor`).

### 3. `rbsecp256k1`'s spurious `rubyzip ~> 2.3` runtime dep

The `rbsecp256k1` gem (which `eth` uses for ECDSA signature
recovery/verification) declares a runtime dependency on
`rubyzip ~> 2.3` in its `.gemspec`. In reality, `rubyzip` is only used
inside `rbsecp256k1`'s `extconf.rb` to download and unpack the
libsecp256k1 C source archive at **build time** — it has zero runtime
use of rubyzip. This is an upstream bug in `rbsecp256k1`'s gemspec and
every published version since 5.0.0 carries it.

Discourse's main bundle now pins `rubyzip 3.2.2`. So when Discourse's
plugin loader calls `Gem::Specification#activate` on `rbsecp256k1`
during boot, RubyGems sees the active rubyzip 3.x and the
`~> 2.3` constraint refuses to resolve, raising:

```
Gem::ConflictError: Unable to activate rbsecp256k1-6.0.0,
because rubyzip-3.2.2 conflicts with rubyzip (~> 2.3)
```

(`--ignore-dependencies` skips install-time resolution but RubyGems
still validates deps at activation time, so we can't simply ignore it.)

The workaround in `plugin.rb` does three things, all idempotent across
container rebuilds:

1. Pre-install `rbsecp256k1` ourselves into the plugin's gem dir using
   `Bundler.with_unbundled_env { system('gem install ...') }`.
2. Open the installed `.gemspec` on disk and strip exactly the line
   `s.add_runtime_dependency(%q<rubyzip>.freeze, ["~> 2.3".freeze])`
   using a precise regex (atomic temp-file + rename so a concurrent
   reader can never see a half-written file).
3. Call `Gem::Specification.reset` to invalidate the cached spec, then
   declare `gem 'rbsecp256k1', '6.0.0', require: false` normally.
   Discourse's plugin loader sees the gem already installed, reads the
   patched spec, and activates it without conflict. A
   `Rails.logger.info` line is emitted when the patch is applied so the
   shim is visible in production logs.

`rubyzip` still needs to be on the system gem path for
`rbsecp256k1`'s `extconf.rb` to succeed at build time, which is why
the `before_code: gem install rubyzip` hook in `app.yml` is still
required (see [Installation](#installation) above).

> **Local development note:** the `before_code` hook only runs during
> `./launcher rebuild app`. If you run Discourse locally outside the Docker
> bootstrap (e.g. `d/rails s` in a dev setup), install rubyzip once by hand
> (`gem install rubyzip`) so `rbsecp256k1`'s native build can find it.
> Do **not** work around this by declaring `gem 'rubyzip', ...` in
> `plugin.rb` — that reintroduces the activation conflict with Discourse's
> bundled rubyzip 3.x described above.

## Tests

The plugin includes standalone minitest unit and integration scripts for ENS
resolution and Society Protocol resolution. These run outside the full Discourse
suite.

### Frontend dependencies and bundle

The widget uses the Vue packages from Layers (`components`, `components.evm`,
and `styles`), with wallet dependencies aligned to `layers.evm` 4.0.3. Discourse
is not a Nuxt app, so the Nuxt layer itself is not installed. Wallet selection
and connection stay in the shared `EvmConnect` component; the local adapter
supplies Discourse's message endpoint and authentication callback.

Use Node.js 24 and pnpm to install the pinned dependencies, apply the Discourse
compatibility patch, run regression tests, and rebuild the checked-in bundle:

```bash
cd ui
pnpm install --frozen-lockfile
pnpm test
pnpm build
```

The build rejects missing optional wallet SDK dependencies. The parser patch
and its rationale are documented in `ui/patches/README.md`.

### Unit tests (no network needed)

```bash
ruby test/ens_unit_test.rb
ruby test/society_unit_test.rb
ruby test/voting_unit_test.rb
```

### Integration tests (require an Ethereum RPC endpoint)

```bash
ruby test/ens_integration_test.rb
ruby test/society_integration_test.rb
```

By default, integration tests use a public RPC. Set `RPC_URL` for a dedicated
provider:

```bash
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY ruby test/society_integration_test.rb
```

To test the positive Society resolution path, set an address that holds a
profile badge:

```bash
RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY \
SOCIETY_ADDRESS=0x... \
ruby test/society_integration_test.rb
```

### Run all tests

```bash
for f in test/*_test.rb; do ruby "$f"; done
```

## How it works

When a user clicks the Ethereum login button, the plugin opens a dedicated
authentication page. The user connects their wallet, signs a SIWE message,
and is authenticated via the OmniAuth strategy on the server side.

### Sign-up path

For a brand-new account, the plugin resolves available identities and stores
them in user custom fields:

- `wallet_address` — the verified Ethereum address.
- `ens_name` / `ens_avatar` — resolved server-side if an RPC URL is configured.
  The ENS name is suggested as the default username; the ENS avatar is fetched
  from the ENS metadata service.
- `society_badge_id` / `society_name` / `society_avatar` / `society_bio` —
  resolved from Society Protocol using the configured subgraph (default) or
  direct RPC fallback.

A default `preferred_identity` is chosen automatically: Society if available,
otherwise ENS, otherwise wallet. `DisplayNameApplier` then applies it to
`user.name` and enqueues an avatar download if an avatar URL is present. The
Discourse username itself is never rewritten after account creation.

### Existing-user login path

For returning users, the login path does not block on network calls. It only
cheaply refreshes ENS from the already-resolved `auth_token.info` and queues a
throttled `RefreshSiweIdentity` background job to update Society data at most
once every 24 hours. This keeps logins fast even if Society Protocol's
subgraph or RPC is slow or unavailable.

### Display-identity toggle

Users with more than one available identity can switch at any time from
**Preferences > Profile**. The `update_identity` endpoint validates the choice
(e.g. rejecting Society if no badge exists), persists the new preference, and
re-applies `DisplayNameApplier`. On failure, the UI reverts the selection.

Because the profile page's plugin outlet is at the bottom of the form, a small
initializer (`assets/javascripts/discourse/initializers/siwe-identity-reposition.js.es6`)
moves the selector to the top of the profile section after render.

### Token gating with Society badges

The plugin can map Society Protocol ERC-1155 badges to Discourse groups. When a
user logs in, their wallet is resolved against the subgraph, every badge they
hold is stored, and their group memberships are synced automatically.

To enable it, set **Siwe society group mapping** to pairs of `badge_id:group_name`
separated by `|`:

```text
13:governors|25:core-team|28:moderators
```

Each mapped group must already exist in Discourse and should be a **manual**
(not automatic/trust-level) group. Configure the group's flair image, title, and
color to visually represent the badge on posts.

Membership changes are applied at the next identity refresh (account creation
or login, at most once every 24 hours), not in real time. A user who receives a
badge gets group access when they next log in; a user who loses a badge is
removed from the group when the refresh runs. To force a full re-sync for every
SIWE user, run the migration task with the `force` flag (see below).

#### Official Society badge registry

The Society Protocol Badges contract exposes official badge IDs for Society's
own forum roles. IDs 17–23 do not currently exist on-chain, so the registry is
non-contiguous:

| Badge ID | Name             | Typical forum use |
| -------- | ---------------- | ----------------- |
| 11       | SP DAO           | DAO members       |
| 12       | Security Council | Security council  |
| 13       | Governor         | Governors         |
| 14       | Bronze VIP       | Bronze VIP tier   |
| 15       | Silver VIP       | Silver VIP tier   |
| 16       | Gold VIP         | Gold VIP tier     |
| 24       | Advisor          | Advisors          |
| 25       | Core Team        | Core team         |
| 26       | Contributor      | Contributors      |
| 27       | ICO Participant  | ICO participants  |
| 28       | Moderator        | Moderators        |

The mechanism is generic: community badges (issued by external communities
through the Web3 Outpost) also appear in `user.badges` and can be mapped the
same way. A future phase will add a no-code admin UI so external communities can
gate their own forums on any token contract without editing code.

### Native Token Governance & Weighted Voting

The plugin embeds an off-chain signaling and token-weighted voting engine natively inside Discourse. Operating on the **Snapshot v1 architectural paradigm**, it provides decentralized governance without requiring third-party SaaS subscriptions ($6,000/yr), Snapshot Hub servers, or external sequencers.

#### Core Capabilities

1. **Gasless EIP-712 Ballots:**
   Voters cast ballots by signing structured EIP-712 messages using their connected wallet (MetaMask, WalletConnect, or Safe multisig). Voting costs **$0 in gas**. Signatures are validated server-side for both EOAs and smart contract wallets (EIP-1271 / EIP-6492).
2. **Historical Snapshot Block Height:**
   When a proposal is initialized, the system automatically calls Ethereum RPC (`EthRpc.eth_block_number`) to lock the exact EVM block height. When votes are cast, voter badge balances are queried via `web3-app-subgraph` at that exact block number, preventing flash loans or post-announcement badge acquisition from manipulating results.
3. **Advanced Tally Engines:**
   - **Weighted Voting (Competitions & Grants):** Voters can split their voting power across multiple options (e.g., 50% to Project Alpha, 30% to Project Beta, 20% to Project Gamma). Proportional power is calculated dynamically.
   - **Single Choice:** Standard single-option voting where 100% of voting power goes to one choice.
   - **Quadratic Voting:** Mitigates whale dominance by scaling effective power quadratically ($\text{Power} = \sqrt{\text{Allocated Badges}}$).
   - **Approval Voting:** Voters can approve any number of acceptable candidates with their full voting weight.
4. **Shielded Voting (Secret Ballots):**
   Active proposals can be configured as **Shielded**. While voting is open (`Time.now.utc < ends_at`), API responses mask individual choices and voting tallies, showing only total voter count. Once the deadline expires or the proposal is closed, final certified tallies and percentage bars are unmasked automatically.
5. **Safe Multisig Execution Payloads:**
   Proposal creators can attach an optional execution payload (`to`, `value`, `data`, `operation`). When a proposal passes, a formatted Gnosis Safe batch transaction payload is generated, allowing DAO signers to execute on-chain outcomes directly via Safe {Wallet} App or `web3-app-contracts`.

#### How to Use Voting (Step-by-Step Guide)

##### For Community Members & Voters

Participating in forum governance proposals is gasless and takes place directly inside Discourse:

1. **Sign in with your Web3 Wallet:**
   - Click the Ethereum login button and sign in using your wallet (MetaMask, WalletConnect, or Safe multisig).
   - Your voting power is tied to your wallet's verified address.
2. **Badge-Based Voting Power:**
   - Voting power is determined by the proposal's configurable **Strategy Rules** (`strategy_rules`), evaluated against badges held at the frozen **Snapshot Block Height**.
   - There are **no mandatory predetermined weights**: the proposal creator decides exactly which badges are eligible and how many votes each holder receives.
   - For example, a proposal can restrict voting solely to **Core Team** badge holders (`#25`) with **2 votes per member** (`"strategy_rules": { "25": 2 }`). Anyone without an eligible badge will have 0 voting power and cannot vote.
   - Because balances are queried at the historical snapshot block, badges acquired after the proposal was initialized cannot be used to vote.
3. **Navigate to the Governance Topic:**
   - Open any topic tagged with `#governance` (or the configured `siwe_voting_tag`).
   - The interactive `sp-vote-widget` appears prominently above the first post.
4. **Inspect the Proposal Details:**
   - Review the proposal title, active/closed badge, snapshot block height, and closing deadline.
   - Check the **"Your Voting Power"** badge in the widget footer to verify your eligible voting power.
5. **Select Your Vote:**
   - **Single Choice:** Click the radio button for your preferred option.
   - **Weighted Voting (Competitions & Grant Allocations):** Enter the percentage share you wish to allocate to each choice (e.g. 50% to Project Alpha, 30% to Project Beta, 20% to Project Gamma). The widget shows your allocated and remaining percentages in real time.
   - **Approval Voting:** Check the box next to all acceptable candidates.
   - **Quadratic Voting:** Distribute weights across options; effective voting power scales as $\sqrt{\text{Allocated Power}}$ to curb whale dominance.
6. **Sign & Cast Ballot (Gasless):**
   - Click **"Sign & Cast Vote"**.
   - Your wallet will prompt you to sign an **EIP-712 structured typed data message** ("Society Protocol Governance").
   - This signature is off-chain and costs **$0 in network gas fees**.
   - Once submitted, your vote is saved and verified against your linked forum account.
7. **Shielded Ballots & Results:**
   - If the proposal is **Shielded**, live choice tallies and percentages remain hidden behind a "Shielded" indicator while voting is active to prevent herd behavior and social pressure.
   - When the voting deadline expires (`ends_at`), certified vote counts, power allocations, and percentage bars unlock automatically.
8. **Executing Passed Proposals (Safe Multisig):**
   - If an approved proposal included an execution payload, a **Safe Multisig Execution Card** appears once closed. DAO signers can click **"Copy Payload"** and import the batch JSON payload directly into Safe {Wallet} App.

---

##### For Forum Administrators & Proposal Creators

Staff and administrators can attach a governance vote to any discussion topic via the Discourse API or curl:

1. **Ensure Settings are Configured:**
   - Under **Admin > Plugins > Settings**:
     - Verify **Siwe voting enabled** is checked.
     - Note your **Siwe voting tag** (default: `governance`).
     - Set **Siwe voting chain id** (default: `1`).
2. **Create the Topic in Discourse:**
   - Create a standard discussion topic detailing the proposal background, options, and rules.
   - Add the `#governance` tag to the topic. Note the topic ID from the URL (e.g. `forum.community.com/t/community-grant-allocation/42` -> topic ID is `42`).
3. **Initialize the Governance Proposal via API:**
   - Send a `POST /sp-voting/proposal` request with Discourse Staff API credentials or a session cookie:

```bash
curl -X POST https://forum.yourcommunity.com/sp-voting/proposal \
  -H "Content-Type: application/json" \
  -H "Api-Key: YOUR_DISCOURSE_API_KEY" \
  -H "Api-Username: admin_username" \
  -d '{
    "topic_id": 42,
    "title": "Core Team Decision #1",
    "options": ["Option Alpha", "Option Beta", "Option Gamma", "Option Delta"],
    "ends_at": "2026-10-15T18:00:00Z",
    "voting_type": "weighted",
    "shielded": true,
    "strategy_rules": {
      "25": 2
    },
    "execution_payload": {
      "to": "0x1234567890123456789012345678901234567890",
      "value": "0",
      "data": "0xa9059cbb000000000000000000000000...",
      "operation": 0
    }
  }'
```

###### Proposal Parameters:

| Parameter | Type | Required | Description |
|---|---|---|---|
| `topic_id` | Integer | Yes | The ID of the Discourse topic where the vote card should attach. |
| `title` | String | Optional | The proposal title. Defaults to the topic title if omitted. |
| `options` | Array[String] | Yes | At least 2 option labels (e.g. `["Option A", "Option B", "Option C"]`). |
| `ends_at` | String (ISO8601) | Yes | Future expiration timestamp (e.g. `"2026-10-15T18:00:00Z"`). |
| `voting_type` | String | Optional | Tally model: `"single_choice"`, `"weighted"`, `"quadratic"`, or `"approval"`. In `"weighted"`, voters split their votes by percentage across choices (e.g. 50% to Option A and 50% to Option B). |
| `shielded` | Boolean | Optional | When `true`, hides intermediate tallies until voting closes. Defaults to site setting `siwe_voting_shielded_default`. |
| `snapshot_block` | Integer | Optional | Historical EVM block number to query voter badge balances. If omitted or `0`, the plugin queries Ethereum RPC and automatically locks the current block height. |
| `strategy_rules` | Object | Optional | Defines which badges are eligible and their voting power. For example, `{"25": 2}` grants holders of the Core Team badge (`#25`) exactly 2 votes each, while anyone without the badge receives 0 votes and cannot vote. |
| `quorum` | Decimal | Optional | Minimum total voting power required for validity. |
| `execution_payload` | Object | Optional | Target contract call parameters (`to`, `value`, `data`, `operation`) formatted for Safe Multisig execution upon passage. |

4. **Automatic Widget Rendering:**
   - Once created, anyone visiting topic `#42` will immediately see the `sp-vote-widget` rendered directly above the first post.

### Backfilling existing users

After deploying the plugin, run the rake task to backfill custom fields, group
memberships, and default display identity for existing SIWE users:

```bash
bundle exec rake siwe:migrate_identities
```

Dry-run first:

```bash
bundle exec rake siwe:migrate_identities[true]
```

To re-sync users who were already migrated — for example, after changing the
badge-to-group mapping — add the `force` flag:

```bash
bundle exec rake siwe:migrate_identities[true,true]
```

(`true` for dry-run, `true` for force.)

The task resolves ENS and Society identities, sets the default preference,
syncs mapped group memberships, and stores the result in user custom fields.
Existing display names are left untouched unless the user toggles their preferred
identity.

## Troubleshooting and engineering notes

This section captures the issues hit during the first deployment and the
information needed to debug or resume work on another machine.

### Boot-time issues encountered

1. **Missing `rubyzip` during C-extension build**
   - Symptom: `rbsecp256k1` fails to compile, complaining that `zip` or
     `rubyzip` is missing.
   - Fix: the `before_code: gem install rubyzip` hook in `app.yml` handles this
     during `./launcher rebuild app`. When running Discourse outside that flow
     (e.g. `d/rails s` in a dev environment), install it once by hand:
     `gem install rubyzip`.
   - Do **not** add `gem 'rubyzip', '2.3.2'` to `plugin.rb` — Discourse's main
     bundle activates rubyzip 3.x and that declaration would cause a
     `Gem::ConflictError` at boot.

2. **`uninitialized constant IdentityStore` in `plugin.rb`**
   - Symptom: `NameError: uninitialized constant IdentityStore` during Discourse
     boot.
   - Fix (already applied): reference the namespaced constant:
     `DiscourseSiwe::IdentityStore::FIELDS.each { ... }`.

3. **`DiscourseSIWE` vs `DiscourseSiwe` namespace mismatch**
   - The repo is consistent and uses `DiscourseSiwe`. If you see this error in a
     local copy, check that every file uses the same PascalCase (`DiscourseSiwe`)
     and not an all-caps `SIWE` variant.

4. **Calling `.each` on the module instead of the constant array**
   - Same root cause as #2: `IdentityStore::FIELDS` was missing the module
     prefix, so Ruby resolved `IdentityStore` to the module object. Fixing the
     namespace also fixes this.

### Wallet sign-in error: "... does not match current domain"

If the wallet (e.g. MetaMask) refuses to sign and shows a message like
`https://localhost:3000 does not match current domain`, it is MetaMask's SIWE
anti-phishing protection ([MetaMask issue #18191](https://github.com/MetaMask/metamask-extension/issues/18191)).
MetaMask verifies that the EIP-4361 message's `domain` and `URI` exactly match
the page origin that requested the signature.

The server builds the SIWE message from `Discourse.base_url`
(`app/controllers/discourse_siwe/auth_controller.rb`). The mismatch means the
browser origin does not equal Discourse's configured base URL. Common causes:

- Browsing `https://localhost:3000` while Discourse is configured as
  `http://localhost:3000` (or `force_https` is off).
- A port mismatch — e.g. an Ember CLI proxy on `:4200` while the backend base
  URL is `:3000`.
- Hostname mismatch — `127.0.0.1` vs `localhost`, or a tunnel/domain not listed
  in `DISCOURSE_HOSTNAME`.

Fix: browse Discourse at the exact URL it is configured for, or adjust
`DISCOURSE_HOSTNAME` / `force_https` to match the real access URL.

### Information to collect when debugging sign-in

To continue debugging on a different machine, gather:

1. The SIWE message text (copy it from the wallet prompt or fetch it with
   `curl "https://HOST/discourse-siwe/message?eth_account=0x...&chain_id=1"`).
   Look at the `domain` and `URI:` lines.
2. The exact URL in the browser's address bar when the sign-in button is clicked.
3. How Discourse is being run (`d/rails s`, `./launcher`, port, HTTPS on/off) and
   the values of `DISCOURSE_HOSTNAME` and `force_https`.
4. The browser console output (full error) and the Network tab entries for
   `/discourse-siwe/message` and the final OmniAuth callback POST.
5. The relevant `log/development.log` lines around the callback — the strategy
   logs failure reasons such as `invalid_nonce`, `expired_message`, or
   `invalid_signature`.

With #1 and #2 the exact mismatch can usually be identified immediately.

## Upstream Compatibility & Updates

- **v1.3.4 Alignment (September 2026):**
  - Ported upstream fixes from `signinwithethereum/discourse-siwe-auth` v1.3.4.
  - Replaced `rbsecp256k1` / `eth` dependency chain with `siwe-rb 0.3.0` + `keccak`.
  - Fixes Docker production rebuild failures (`./launcher rebuild app`) and gem version conflicts on Discourse base images.
  - Included upstream MetaMask reconnection and Ember compatibility patches while preserving custom Society Protocol Shielded Voting features.

## License

MIT / Apache-2.0, same as upstream. See `LICENSE-MIT` and `LICENSE-APACHE`.

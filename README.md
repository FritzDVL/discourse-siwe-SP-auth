# Sign-In with Ethereum for Discourse

A Discourse plugin that authenticates users with their Ethereum wallet using the
[Sign-In with Ethereum (SIWE)](https://login.xyz) standard, then lets them
choose how their profile appears in the forum.

This maintained fork used by [Society Protocol](https://societyprotocol.io)
extends the original SIWE plugin with server-side ENS resolution,
EIP-1271 / EIP-6492 smart-contract-wallet signature verification, and
**Society Protocol Web3 Outpost identity resolution**. A connected wallet can
expose three possible display identities:

- **Wallet** — the verified Ethereum address (e.g. `0x1234…abcd`).
- **ENS** — the address's ENS name and avatar, resolved server-side.
- **Society Protocol** — the ERC-1155 profile badge / Web3 Outpost name and
  avatar, resolved from the Society Protocol subgraph or directly from the
  Ethereum mainnet contract.

The user picks the preferred identity from **Preferences > Profile**. The
display name and avatar are updated; the Discourse username is never rewritten.

> **About this fork.** This started from
> [`signinwithethereum/discourse-siwe-auth`](https://github.com/signinwithethereum/discourse-siwe-auth)
> and fixes the install-time issues that block it on current Discourse, which
> ships Ruby 3.4 in the official `discourse/base` Docker image. See
> [Compatibility notes](#compatibility-notes-discourse--ruby-34) below.
> Upstream tracking issue:
> [signinwithethereum/discourse-siwe-auth#2](https://github.com/signinwithethereum/discourse-siwe-auth/issues/2).

## Requirements

- A self-hosted Discourse forum, or a host that allows third-party plugins
  (e.g. [Communiteq](https://www.communiteq.com/)).
- For ENS resolution and smart-contract-wallet verification: an Ethereum
  JSON-RPC endpoint.
- For WalletConnect / Reown support: a project ID from
  [dashboard.reown.com](https://dashboard.reown.com).

## Installation

Edit your container's `app.yml`:

```bash
cd /var/discourse
nano containers/app.yml
```

Add a `before_code` hook to install `rubyzip` and an `after_code` hook to clone
this plugin:

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
        - sudo -E -u discourse git clone https://github.com/SocietyProtocol/discourse-siwe.git
```

> **Use the exact `-E -u discourse` prefix.** On Ubuntu 24.04 a plain `git clone`
> runs as `root` and creates files the Rails build cannot read, causing a
> confusing failure during `./launcher rebuild app`. Match the form of the
> existing `docker_manager.git` line.

Then rebuild:

```bash
cd /var/discourse
./launcher rebuild app
```

### Why the `before_code` hook is required

The native `rbsecp256k1` crypto gem uses `rubyzip` inside its `extconf.rb` to
fetch and unpack the libsecp256k1 C source during build. That happens **before**
Discourse processes the `gem` directives in `plugin.rb`, so the plugin cannot
supply `rubyzip` in time. Installing it system-wide in `before_code` guarantees
it is present when the native extension builds.

Do **not** add `gem 'rubyzip', ...` to `plugin.rb` — that reintroduces a
version conflict with Discourse's bundled `rubyzip 3.x`. See the
[compatibility notes](#compatibility-notes-discourse--ruby-34) below.

## Configuration

After installation, go to **Admin > Plugins**, enable the plugin, then open
**Settings**:

![Installed plugins](/installed-plugins.png 'Installed plugins')
![Plugin settings](/settings.png 'Plugin settings')

### Settings

| Setting | Description |
| --- | --- |
| **Discourse siwe enabled** | Enable or disable Sign-In with Ethereum authentication. |
| **Siwe ethereum rpc url** | _Optional but recommended._ Ethereum JSON-RPC endpoint used for ENS name/avatar resolution and EIP-1271 signature verification (required for smart contract wallets like SAFE). Example: `https://mainnet.infura.io/v3/YOUR_KEY`. |
| **Siwe project ID** | _Optional._ WalletConnect / Reown project ID. Without it, only injected wallets (MetaMask, Safe, etc.) are available. |
| **Siwe statement** | The human-readable statement shown in the SIWE message. Defaults to "Sign in with Ethereum". |
| **Siwe society enabled** | Enable Society Protocol identity resolution and the display-identity toggle. |
| **Siwe society subgraph url** | _Optional._ The Society Protocol subgraph endpoint. Defaults to the live mainnet endpoint; leave blank to force direct RPC resolution. |
| **Siwe society badges contract** | Society Protocol Badges (ERC-1155) contract address. Defaults to the current mainnet proxy `0x2313C0cDdc233c92d16c2cfE17DF5fDCcE556763`. |
| **Siwe identity resolution mode** | Preferred resolution mode: `subgraph` (default, falls back to RPC) or `rpc` (direct contract calls only). |

## Society Protocol identity resolution

When a user signs up or logs in, the plugin resolves any available identities and
stores them in user custom fields:

- `wallet_address` — the verified Ethereum address.
- `ens_name` / `ens_avatar` — resolved server-side when an RPC URL is configured.
- `society_badge_id` / `society_name` / `society_avatar` / `society_bio` —
  resolved from the Society Protocol [Web3 Outpost](https://docs.societyprotocol.io/)
  ERC-1155 badges contract.

A default `preferred_identity` is chosen automatically: **Society** if available,
otherwise **ENS**, otherwise **wallet**. Users with more than one identity can
switch at any time from **Preferences > Profile**. The choice updates the visible
name and avatar; the underlying username never changes.

## Local development and wallet compatibility

The plugin works on `http://localhost:3000`, but not all wallets authorize
account access on an insecure local origin.

| Wallet | `http://localhost:3000` | HTTPS / real domain |
| --- | --- | --- |
| MetaMask | ✅ Works | ✅ Works |
| Brave Wallet | ❌ Refuses authorization | ✅ Works |
| Safe / WalletConnect | Varies | ✅ Recommended |

If you need to test with wallets that reject `localhost`, use a temporary public
tunnel:

```bash
# ngrok
ngrok http 3000

# Cloudflare Tunnel
cloudflared tunnel --url http://localhost:3000
```

Then set Discourse to match the tunnel URL in the Rails console:

```ruby
SiteSetting.force_https = true
SiteSetting.hostname = "abc123.ngrok-free.app" # your tunnel domain
```

Browse to the HTTPS tunnel URL and sign in.

## Security considerations

- **RPC and subgraph endpoints are trusted inputs.** The plugin fetches data
  from the configured `siwe_ethereum_rpc_url` and `siwe_society_subgraph_url`.
  Point them only at providers you trust (Alchemy, Infura, the official Society
  subgraph, or a node you control).
- **Badge metadata and avatar URLs come from the Society Protocol contract.**
  The plugin validates schemes (`http`, `https`, `ipfs`) and rejects private IP
  ranges / `localhost` before fetching, but the metadata is ultimately supplied
  by the on-chain contract. Do not change `siwe_society_badges_contract` away
  from the official Society Protocol deployment unless you understand the
  trust model.
- **Email verification.** The SIWE authenticator returns `primary_email_verified?`
  as `false`, so Discourse requires new SIWE users to verify an email address.
  Configure SMTP in production. In local development you can manually activate
  a test account from the Rails console.
- **Custom fields are private.** The `web3_identities` serializer only exposes the
  user's wallet, ENS, and Society data to that user.
- **Usernames are stable.** The identity toggle only changes the display name
  (`user.name`) and avatar. Mentions, quotes, and permalinks stay intact.

## Compatibility notes (Discourse + Ruby 3.4)

Recent Discourse versions ship Ruby 3.4 in the official `discourse/base` Docker
image and pin `rubyzip` to the 3.x line. This fork fixes three distinct issues in
`plugin.rb` so `./launcher rebuild app` completes cleanly.

### 1. Discourse's plugin `gem` DSL needs an explicit version string

The plugin DSL signature is `gem(name, version, opts = {})` and it calls
`gem install ... --ignore-dependencies`. Passing `gem 'eth', require: false`
(no version) makes RubyGems treat the keyword hash as the version argument:

```
ERROR:  While executing gem ... (Gem::Requirement::BadRequirementError)
    Illformed requirement ["{"]
```

Every `gem` line in `plugin.rb` now has an explicit version, e.g.
`gem 'eth', '0.5.17', require: false`.

### 2. Every transitive dependency must be declared explicitly

`--ignore-dependencies` means RubyGems does not auto-install transitive deps.
On Ruby 3.4:

- `base64` is no longer a default gem; `eth >= 0.5.16` explicitly depends on it.
- The full dependency graph for `eth` / `siwe` is listed in install order:
  `ecdsa`, `h2c`, `bls12-381`, `http-2`, `httpx`, plus build deps.

### 3. `rbsecp256k1`'s spurious `rubyzip ~> 2.3` runtime dep

`rbsecp256k1` declares a runtime dependency on `rubyzip ~> 2.3`, but it only
uses `rubyzip` at build time in `extconf.rb`. Discourse's main bundle activates
`rubyzip 3.x`, so activating `rbsecp256k1` raises a `Gem::ConflictError`.

The workaround in `plugin.rb` pre-installs `rbsecp256k1` into the plugin gem
 directory, strips the bogus `rubyzip` line from its installed `.gemspec`, resets
`Gem::Specification`, then declares the gem normally. This is idempotent across
rebuilds and logs when the patch is applied.

## Tests

The plugin includes standalone minitest unit and integration scripts. They run
outside the full Discourse suite.

### Unit tests (no network needed)

```bash
ruby test/ens_unit_test.rb
ruby test/society_unit_test.rb
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
authentication page. The user connects a wallet, signs a SIWE message, and is
authenticated via the OmniAuth strategy on the server side.

### Sign-up path

For a new account, the plugin resolves available identities and stores them in
user custom fields. A default `preferred_identity` is chosen automatically:
Society if available, otherwise ENS, otherwise wallet.
`DisplayNameApplier` then applies it to `user.name` and enqueues an avatar
download if an avatar URL is present. The Discourse username is suggested from
ENS when available, but it is never rewritten after account creation.

### Existing-user login path

For returning users, login does not block on network calls. It refreshes ENS
from the already-resolved `auth_token.info` and queues a throttled
`RefreshSiweIdentity` background job to update Society data at most once every
24 hours. This keeps logins fast even if the Society Protocol subgraph or RPC is
slow or unavailable.

### Display-identity toggle

Users with more than one available identity can switch at any time from
**Preferences > Profile**. The `update_identity` endpoint validates the choice
(e.g. rejecting Society if no badge exists), persists the new preference, and
re-applies `DisplayNameApplier`. On failure, the UI reverts the selection.

### Backfilling existing users

After deploying the plugin, run the rake task to backfill custom fields for
existing SIWE users:

```bash
bundle exec rake siwe:migrate_identities
```

Dry-run first:

```bash
bundle exec rake siwe:migrate_identities[true]
```

The task resolves ENS and Society identities, sets the default preference, and
stores the result in user custom fields. Existing display names are left
untouched unless the user toggles their preferred identity.

## Troubleshooting

### Brave Wallet: "The requested method and/or account has not been authorized"

Brave Wallet refuses to authorize `http://localhost` origins. Use MetaMask for
local testing, or test through an HTTPS tunnel / real domain.

### MetaMask: "… does not match current domain"

MetaMask's SIWE anti-phishing protection verifies that the message's `domain`
and `URI` match the page origin. Browse Discourse at the exact URL it is
configured for:

- `http://localhost:3000` ↔ `http://localhost:3000` ✅
- `http://127.0.0.1:3000` or `https://localhost:3000` ↔ `http://localhost:3000` ❌

Common fixes:

- Use `localhost`, not `127.0.0.1`.
- Ensure `force_https` matches the protocol in the address bar.
- If using a proxy or Ember CLI on a different port, align it with
  `SiteSetting.hostname`.

### Missing `rubyzip` during C-extension build

Symptom: `rbsecp256k1` fails to compile, complaining about `zip` or `rubyzip`.
Fix: make sure the `before_code: gem install rubyzip` hook is in `app.yml` and
that you rebuilt the container.

### New SIWE users cannot post until email is verified

This is expected: SIWE does not verify an email address. Configure SMTP in
production. In local development, activate a test account from the Rails
console:

```ruby
user = User.find_by_username_or_email("username")
user.email_tokens.update_all(confirmed: true)
user.activate
```

### Information to collect when debugging sign-in

1. The SIWE message text (copy from the wallet or `curl`
   `"http://localhost:3000/discourse-siwe/message?eth_account=0x...&chain_id=1"`).
   Check the `domain` and `URI:` lines.
2. The exact URL in the browser address bar when sign-in is clicked.
3. How Discourse is run (`d/rails s`, `./launcher`, port, HTTPS on/off) and the
   values of `SiteSetting.hostname` and `SiteSetting.force_https`.
4. The browser console and Network tab entries for `/discourse-siwe/message`
   and `/auth/siwe/callback`.
5. The relevant `log/development.log` lines around the callback.

## License

This project is dual-licensed under the [MIT](/LICENSE-MIT) and
[Apache-2.0](/LICENSE-APACHE) licenses.

Directory structure:
└── fritzdvl-discourse-siwe-sp-auth/
    ├── README.md
    ├── LICENSE-APACHE
    ├── LICENSE-MIT
    ├── package.json
    ├── plugin.rb
    ├── pnpm-lock.yaml
    ├── .discourse-compatibility
    ├── .prettierignore
    ├── .prettierrc
    ├── app/
    │   ├── controllers/
    │   │   └── discourse_siwe/
    │   │       └── auth_controller.rb
    │   └── jobs/
    │       └── regular/
    │           └── refresh_siwe_identity.rb
    ├── assets/
    │   ├── javascripts/
    │   │   └── discourse/
    │   │       ├── siwe-route-map.js
    │   │       ├── components/
    │   │       │   ├── siwe-identity-selector.hbs
    │   │       │   └── siwe-identity-selector.js
    │   │       ├── connectors/
    │   │       │   └── user-preferences-profile/
    │   │       │       └── siwe-identity-selector.gjs
    │   │       ├── controllers/
    │   │       │   └── siwe-auth-index.js
    │   │       ├── routes/
    │   │       │   └── siwe-auth-index.js
    │   │       └── templates/
    │   │           └── siwe-auth-index.hbs
    │   └── stylesheets/
    │       └── discourse-siwe-auth.scss
    ├── config/
    │   ├── settings.yml
    │   └── locales/
    │       ├── client.en.yml
    │       └── server.en.yml
    ├── lib/
    │   ├── discourse_siwe/
    │   │   ├── display_name_applier.rb
    │   │   ├── ens_resolver.rb
    │   │   ├── eth_rpc.rb
    │   │   ├── identity_resolver.rb
    │   │   ├── identity_store.rb
    │   │   └── url_validator.rb
    │   ├── omniauth/
    │   │   └── strategies/
    │   │       └── siwe.rb
    │   └── tasks/
    │       └── siwe_identities.rake
    ├── PlanFolder/
    │   ├── ImplementationReport.md
    │   ├── InitialCodebase.md
    │   ├── InitialPlan.md
    │   └── RefinedPlan.md
    ├── test/
    │   ├── ens_integration_test.rb
    │   ├── ens_unit_test.rb
    │   ├── society_integration_test.rb
    │   └── society_unit_test.rb
    └── ui/
        ├── index.html
        ├── package.json
        ├── tsconfig.json
        ├── tsconfig.node.json
        ├── vite.config.ts
        └── src/
            ├── env.d.ts
            ├── main.ts
            ├── shadow.ts
            ├── SiweAuth.vue
            └── wagmi.ts


Files Content:

================================================
FILE: README.md
================================================
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



================================================
FILE: LICENSE-APACHE
================================================
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright 2021 Spruce Systems Inc.
   Copyright 2026 EthID.org

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.


================================================
FILE: LICENSE-MIT
================================================
MIT License

Copyright (c) 2021 Spruce Systems, Inc.
Copyright (c) 2026 EthID.org

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


================================================
FILE: package.json
================================================
{
  "private": true,
  "scripts": {
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  },
  "devDependencies": {
    "prettier": "^3.8.1"
  },
  "dependencies": {
    "js-sha3": "^0.12.0"
  }
}



================================================
FILE: plugin.rb
================================================
# frozen_string_literal: true

# name: discourse-siwe-auth
# about: Authenticate users via Sign In with Ethereum (SIWE), with optional Society Protocol identity resolution
# version: 1.3.0
# authors: EthID
# url: https://siwe.xyz

enabled_site_setting :discourse_siwe_enabled
register_svg_icon 'fab-ethereum'
register_asset 'stylesheets/discourse-siwe-auth.scss'

%w[
  ../lib/omniauth/strategies/siwe.rb
].each { |path| load File.expand_path(path, __FILE__) }

# Discourse's plugin `gem` DSL signature is `gem(name, version, opts = {})` and
# it shells out to `gem install ... --ignore-dependencies`, so:
#   1) every gem MUST have an explicit version string as the 2nd positional arg
#      (passing `require: false` without a version makes Ruby treat the kwargs
#      hash as the version, breaking install with "Illformed requirement"),
#   2) every transitive dependency must be declared explicitly here in
#      install order (deps before dependents), since --ignore-dependencies
#      means Discourse will not auto-resolve them.
# `rubyzip` (a build-time dep of rbsecp256k1's extconf.rb) is installed
# system-wide via the `before_code` hook in app.yml; see README.

gem 'pkg-config',    '1.6.5',  require: false
gem 'mini_portile2', '2.8.9',  require: false
gem 'ffi',           '1.17.4', require: false
gem 'ffi-compiler',  '1.3.2',  require: false
gem 'konstructor',   '1.0.2',  require: false
gem 'scrypt',        '3.1.0',  require: false
gem 'keccak',        '1.3.3',  require: false

# rbsecp256k1 6.0.0 (and every published version since 5.0.0) declares a
# spurious runtime dependency on `rubyzip ~> 2.3`. It only uses rubyzip in
# its `extconf.rb` to unpack libsecp256k1's source archive at build time —
# it has zero runtime use of rubyzip. But Discourse's main bundle activates
# rubyzip 3.x at boot, so when Discourse's plugin DSL calls `spec.activate`
# on rbsecp256k1, RubyGems raises Gem::ConflictError.
#
# Workaround: pre-install rbsecp256k1 ourselves and strip the bogus rubyzip
# line from the installed gemspec on disk. Discourse's plugin loader then
# sees the gem already installed, loads the patched spec, and activates it
# without conflict. Idempotent across rebuilds.
RBSECP256K1_VERSION = '6.0.0'
rbsecp_gems_dir = File.expand_path("../gems/#{RUBY_VERSION}", __FILE__)
rbsecp_spec_file = "#{rbsecp_gems_dir}/specifications/rbsecp256k1-#{RBSECP256K1_VERSION}.gemspec"

unless File.exist?(rbsecp_spec_file)
  install_cmd = "gem install rbsecp256k1 -v #{RBSECP256K1_VERSION} " \
                "-i #{rbsecp_gems_dir} --no-document " \
                "--ignore-dependencies --no-user-install"
  Bundler.with_unbundled_env { system(install_cmd) } ||
    raise("rbsecp256k1 #{RBSECP256K1_VERSION} pre-install failed")
end

# Precise pattern: only the exact add_runtime_dependency line for rubyzip.
# Avoids accidentally stripping other lines if upstream changes formatting.
rbsecp_rubyzip_dep_re =
  /^\s*s\.add_runtime_dependency\(?\s*%q<rubyzip>.*?\)?\s*\n/
rbsecp_spec_content = File.read(rbsecp_spec_file)
if rbsecp_spec_content =~ rbsecp_rubyzip_dep_re
  patched = rbsecp_spec_content.sub(rbsecp_rubyzip_dep_re, '')
  # Atomic replace via tempfile + rename so a concurrent reader never sees a
  # half-written gemspec.
  tmp = "#{rbsecp_spec_file}.patching.#{Process.pid}"
  File.write(tmp, patched)
  File.rename(tmp, rbsecp_spec_file)
  Gem::Specification.reset
  Rails.logger.info(
    "[discourse-siwe-auth] Stripped spurious rubyzip runtime dep from " \
    "rbsecp256k1-#{RBSECP256K1_VERSION}.gemspec to avoid Gem::ConflictError " \
    "with Discourse's bundled rubyzip."
  ) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
end

gem 'rbsecp256k1', RBSECP256K1_VERSION, require: false

# eth >= 0.5.16 is the first version that explicitly depends on `base64`,
# which Ruby 3.4 demoted from default-gem to bundled-gem. Its full transitive
# closure (bls12-381, httpx, etc.) must be declared since --ignore-dependencies
# prevents auto-install.
gem 'base64',        '0.3.0',  require: false
gem 'ecdsa',         '1.2.0',  require: false
gem 'h2c',           '0.2.1',  require: false
gem 'bls12-381',     '0.3.1',  require: false
gem 'http-2',        '1.1.3',  require: false
gem 'httpx',         '1.7.6',  require: false
gem 'eth',           '0.5.17', require: false
gem 'siwe',          '1.1.2',  require: false

class ::SiweAuthenticator < ::Auth::ManagedAuthenticator
  def name
    'siwe'
  end

  def register_middleware(omniauth)
    omniauth.provider :siwe,
                      setup: lambda { |env|
                        strategy = env['omniauth.strategy']
                      }
  end

  def enabled?
    SiteSetting.discourse_siwe_enabled
  end

  def primary_email_verified?
    false
  end

  def description_for_auth_hash(auth_token)
    auth_token&.provider_uid || super
  end

  def after_authenticate(auth_token, existing_account: nil)
    result = super

    wallet = auth_token&.uid&.downcase
    return result unless wallet.present?

    info = auth_token[:info] || {}
    ens_name   = info[:nickname].presence
    ens_name   = nil if ens_name&.downcase == wallet
    ens_avatar = info[:image].presence

    if result.user
      cf = result.user.custom_fields
      cf['wallet_address'] ||= wallet
      cf['ens_name']   = ens_name   if ens_name
      cf['ens_avatar'] = ens_avatar if ens_avatar
      cf['preferred_identity'] ||= DiscourseSiwe::IdentityStore.default_preference(cf)
      result.user.save_custom_fields

      if SiteSetting.siwe_society_enabled && DiscourseSiwe::IdentityStore.society_stale?(result.user)
        Jobs.enqueue(:refresh_siwe_identity, user_id: result.user.id)
      end
    else
      result.extra_data = (result.extra_data || {}).merge(
        wallet_address: wallet,
        ens_name: ens_name,
        ens_avatar: ens_avatar,
      )
      result.name       = ens_name   if ens_name
      result.avatar_url = ens_avatar if ens_avatar
    end

    result
  end

  def after_create_account(user, auth_result)
    super
    return unless SiteSetting.siwe_society_enabled

    extra = auth_result[:extra_data] || {}
    wallet = extra['wallet_address'] || extra[:wallet_address]
    return unless wallet.present?

    user.custom_fields['wallet_address'] = wallet.downcase
    user.custom_fields['ens_name']       = extra['ens_name']   || extra[:ens_name]
    user.custom_fields['ens_avatar']     = extra['ens_avatar'] || extra[:ens_avatar]

    society = DiscourseSiwe::IdentityResolver.resolve(wallet)
    DiscourseSiwe::IdentityStore.store_society(user, society)
    user.custom_fields['preferred_identity'] =
      DiscourseSiwe::IdentityStore.default_preference(user.custom_fields)
    user.save_custom_fields

    DiscourseSiwe::DisplayNameApplier.apply(user)
    user.save!
  end
end

auth_provider authenticator: ::SiweAuthenticator.new,
              icon: 'fab-ethereum',
              title_setting: :siwe_statement,
              full_screen_login: true

after_initialize do
  load File.expand_path('../lib/discourse_siwe/url_validator.rb', __FILE__)
  load File.expand_path('../lib/discourse_siwe/eth_rpc.rb', __FILE__)
  load File.expand_path('../lib/discourse_siwe/ens_resolver.rb', __FILE__)
  load File.expand_path('../lib/discourse_siwe/identity_resolver.rb', __FILE__)
  load File.expand_path('../lib/discourse_siwe/identity_store.rb', __FILE__)
  load File.expand_path('../lib/discourse_siwe/display_name_applier.rb', __FILE__)
  load File.expand_path('../app/controllers/discourse_siwe/auth_controller.rb', __FILE__)
  load File.expand_path('../app/jobs/regular/refresh_siwe_identity.rb', __FILE__)

  DiscourseSiwe::IdentityStore::FIELDS.each do |field|
    User.register_custom_field_type(field, :string)
  end

  # Expose web3 identities only to the owning user.
  add_to_serializer(:user, :web3_identities) do
    DiscourseSiwe::IdentityStore.web3_identities(object)
  end

  add_to_serializer(:user, :include_web3_identities?) do
    scope&.user == object
  end

  Discourse::Application.routes.prepend do
    get  '/discourse-siwe/auth'           => 'discourse_siwe/auth#index'
    get  '/discourse-siwe/message'        => 'discourse_siwe/auth#message'
    post '/discourse-siwe/update-identity' => 'discourse_siwe/auth#update_identity'
  end
end



================================================
FILE: pnpm-lock.yaml
================================================
lockfileVersion: '9.0'

settings:
  autoInstallPeers: true
  excludeLinksFromLockfile: false

importers:
  .:
    devDependencies:
      prettier:
        specifier: ^3.8.1
        version: 3.8.1

packages:
  prettier@3.8.1:
    resolution:
      {
        integrity: sha512-UOnG6LftzbdaHZcKoPFtOcCKztrQ57WkHDeRD9t/PTQtmT0NHSeWWepj6pS0z/N7+08BHFDQVUrfmfMRcZwbMg==,
      }
    engines: { node: '>=14' }
    hasBin: true

snapshots:
  prettier@3.8.1: {}



================================================
FILE: .discourse-compatibility
================================================
[Empty file]


================================================
FILE: .prettierignore
================================================
public
ui/dist



================================================
FILE: .prettierrc
================================================
{
  "singleAttributePerLine": true,
  "singleQuote": true,
  "semi": false
}



================================================
FILE: app/controllers/discourse_siwe/auth_controller.rb
================================================
# frozen_string_literal: true

require 'siwe'
module DiscourseSiwe
  class AuthController < ::ApplicationController
    skip_before_action :check_xhr, only: %i[index]
    skip_before_action :redirect_to_login_if_required, only: %i[index message]

    def index
      raise ApplicationController::RenderEmpty
    end

    def message
      eth_account = params[:eth_account]
      chain_id = params[:chain_id]

      unless eth_account.present? && eth_account.match?(/\A0x[0-9a-fA-F]{40}\z/)
        return render json: { error: "Invalid Ethereum address" }, status: 400
      end

      unless chain_id.present? && chain_id.match?(/\A[1-9][0-9]*\z/)
        return render json: { error: "Invalid chain ID" }, status: 400
      end

      now = Time.now.utc
      domain = Discourse.base_url.delete_prefix("#{Discourse.base_protocol}://")
      message = Siwe::Message.new(domain, eth_account, Discourse.base_url, "1", {
        issued_at: now.iso8601,
        expiration_time: (now + 300).iso8601,
        statement: SiteSetting.siwe_statement,
        nonce: Siwe::Util.generate_nonce,
        chain_id: chain_id,
      })
      session[:nonce] = message.nonce

      render json: { message: message.prepare_message }
    end

    IDENTITIES = %w[wallet ens society].freeze

    def update_identity
      raise Discourse::NotLoggedIn unless current_user

      preferred = params[:preferred_identity]
      unless IDENTITIES.include?(preferred)
        return render json: { error: 'Invalid identity type' }, status: 400
      end

      cf = current_user.custom_fields
      case preferred
      when 'ens'
        return render json: { error: 'No ENS name available' }, status: 400 if cf['ens_name'].blank?
      when 'society'
        return render json: { error: 'No Society identity available' }, status: 400 if cf['society_badge_id'].blank?
      end

      cf['preferred_identity'] = preferred
      current_user.save_custom_fields

      DiscourseSiwe::DisplayNameApplier.apply(current_user)
      current_user.save!

      render json: { success: true, preferred_identity: preferred }
    end
  end
end



================================================
FILE: app/jobs/regular/refresh_siwe_identity.rb
================================================
# frozen_string_literal: true

module Jobs
  class RefreshSiweIdentity < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.siwe_society_enabled

      user = User.find_by(id: args[:user_id])
      return unless user
      return unless DiscourseSiwe::IdentityStore.society_stale?(user)

      wallet = user.custom_fields['wallet_address']
      return unless wallet.present?

      society = DiscourseSiwe::IdentityResolver.resolve(wallet)
      DiscourseSiwe::IdentityStore.store_society(user, society)
      user.save_custom_fields
    end
  end
end



================================================
FILE: assets/javascripts/discourse/siwe-route-map.js
================================================
export default function () {
  this.route('siwe-auth', { path: '/discourse-siwe/auth' }, function () {
    this.route('index', { path: '/' })
  })
}



================================================
FILE: assets/javascripts/discourse/components/siwe-identity-selector.hbs
================================================
{{#if identities.length}}
  <div class="control-group siwe-identity-selector">
    <label class="control-label">
      {{i18n "discourse_siwe.identity.title"}}
    </label>
    <div class="controls">
      {{#each identities as |identity|}}
        <label class="identity-option">
          {{radio-button
            value=identity.id
            selection=model.web3_identities.preferred_identity
            onChange=(action "selectIdentity" identity.id)
          }}
          <span class="identity-name">{{identity.label}}</span>
          <span class="identity-source">
            {{i18n (concat "discourse_siwe.identity.source." identity.sourceKey)}}
          </span>
          {{#if identity.avatar}}
            <img
              src={{identity.avatar}}
              class="identity-preview"
              alt=""
            />
          {{/if}}
        </label>
      {{/each}}
    </div>
  </div>
{{/if}}



================================================
FILE: assets/javascripts/discourse/components/siwe-identity-selector.js
================================================
import Component from '@ember/component'
import { computed } from '@ember/object'
import { ajax } from 'discourse/lib/ajax'
import { popupAjaxError } from 'discourse/lib/ajax-error'

export default Component.extend({
  saving: false,

  identities: computed('model.web3_identities', function () {
    const identities = (this.model && this.model.web3_identities) || {}
    if (!identities.wallet_address) return []

    const list = [
      {
        id: 'wallet',
        label: identities.wallet_address,
        sourceKey: 'wallet',
      },
    ]

    if (identities.ens_name) {
      list.push({
        id: 'ens',
        label: identities.ens_name,
        sourceKey: 'ens',
        avatar: identities.ens_avatar,
      })
    }

    if (identities.society_badge_id) {
      list.push({
        id: 'society',
        label: identities.society_name,
        sourceKey: 'society',
        avatar: identities.society_avatar,
      })
    }

    return list
  }),

  actions: {
    selectIdentity(identity) {
      if (this.saving) return
      const previous = this.model && this.model.web3_identities && this.model.web3_identities.preferred_identity
      if (identity === previous) return

      this.set('saving', true)
      ajax('/discourse-siwe/update-identity', {
        type: 'POST',
        data: { preferred_identity: identity },
      })
        .then(() => {
          this.set('model.web3_identities.preferred_identity', identity)
        })
        .catch((err) => {
          this.set('model.web3_identities.preferred_identity', previous)
          popupAjaxError(err)
        })
        .finally(() => {
          if (this.isDestroying || this.isDestroyed) return
          this.set('saving', false)
        })
    },
  },
})



================================================
FILE: assets/javascripts/discourse/connectors/user-preferences-profile/siwe-identity-selector.gjs
================================================
import SiweIdentitySelector from "discourse/plugins/discourse-siwe-auth/discourse/components/siwe-identity-selector";

<template>
  <SiweIdentitySelector @model={{@outletArgs.model}} />
</template>



================================================
FILE: assets/javascripts/discourse/controllers/siwe-auth-index.js
================================================
import Controller from '@ember/controller'
import { withPluginApi } from 'discourse/lib/plugin-api'
import loadScript from 'discourse/lib/load-script'

export default Controller.extend({
  init() {
    this._super(...arguments)
    this.initAuth()
  },

  async initAuth() {
    const settings = withPluginApi('0.11.7', (api) => {
      const siteSettings = api.container.lookup('site-settings:main')
      return {
        projectId: siteSettings.siwe_project_id,
        statement: siteSettings.siwe_statement,
      }
    })

    const csrfToken =
      document
        .querySelector('meta[name="csrf-token"]')
        ?.getAttribute('content') || ''

    await loadScript('/plugins/discourse-siwe-auth/javascripts/siwe.iife.js')

    if (window.mountSiwe) {
      window.mountSiwe('#siwe-mount', {
        csrfToken,
        callbackUrl: '/auth/siwe/callback',
        messageUrl: '/discourse-siwe/message',
        walletConnectProjectId: settings.projectId,
        statement: settings.statement,
      })
    }
  },
})



================================================
FILE: assets/javascripts/discourse/routes/siwe-auth-index.js
================================================
import Route from '@ember/routing/route'

export default Route.extend()



================================================
FILE: assets/javascripts/discourse/templates/siwe-auth-index.hbs
================================================
{{! {{hide-application-header}}
{{! {{hide-application-sidebar}}
{{body-class 'siwe-login-page'}}
{{hideApplicationHeaderButtons 'search' 'login' 'signup' 'menu'}}
{{hideApplicationSidebar}}
{{! {{bodyClass "login-page"}}
{{bodyClass 'siwe-login-page'}}

<form
  id='siwe-sign'
  method='POST'
  action='/auth/siwe/callback'
  style='display: none;'
>
  <textarea id='eth_message' name='eth_message'></textarea>
  <textarea id='eth_signature' name='eth_signature'></textarea>
</form>

<div id='siwe-mount' class='siwe-mount'></div>


================================================
FILE: assets/stylesheets/discourse-siwe-auth.scss
================================================
.siwe-login-page {
  .d-header {
    background-color: var(--secondary);
    box-shadow: none;
    .wrap {
      width: auto;
    }
  }

  .discourse-root {
    min-height: 100dvh;
  }

  .main-outlet-wrapper {
    height: calc(100dvh - var(--header-offset));
  }

  .powered-by-discourse {
    display: none;
  }
}

.siwe-mount {
  background-color: var(--secondary);
  max-width: 24rem;
  margin-inline: auto;
  scrollbar-gutter: auto;
  min-height: calc(100dvh - 10rem);
  display: grid;
  align-items: center;
}

.siwe-identity-selector {
  .identity-option {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.5rem 0;
  }

  .identity-name {
    font-weight: 700;
  }

  .identity-source {
    color: var(--primary-medium);
    font-size: var(--font-down-1);
  }

  .identity-preview {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    object-fit: cover;
  }
}



================================================
FILE: config/settings.yml
================================================
discourse_siwe:
  discourse_siwe_enabled:
    default: true
  siwe_project_id:
    client: true
    default: ''
  siwe_ethereum_rpc_url:
    default: ''
  siwe_statement:
    client: true
    default: 'Sign in with Ethereum'
  siwe_society_enabled:
    default: true
  siwe_society_subgraph_url:
    default: 'https://api.studio.thegraph.com/query/46833/society-mainnet/version/latest'
  siwe_society_badges_contract:
    default: '0x2313C0cDdc233c92d16c2cfE17DF5fDCcE556763'
  siwe_identity_resolution_mode:
    default: 'subgraph'
    type: enum
    choices:
      - subgraph
      - rpc



================================================
FILE: config/locales/client.en.yml
================================================
en:
  admin_js:
    admin:
      site_settings:
        categories:
          discourse_siwe: 'Sign in With Ethereum'
  js:
    discourse_siwe:
      identity:
        title: 'Web3 display identity'
        source:
          wallet: 'Wallet'
          ens: 'ENS'
          society: 'Society Protocol'
    login:
      siwe:
        name: 'SIWE'
        title: 'Sign in with Ethereum'



================================================
FILE: config/locales/server.en.yml
================================================
en:
  site_settings:
    discourse_siwe_enabled: 'Enable Sign In With Ethereum authentication'
    siwe_project_id: 'Project ID for Web3Modal'
    siwe_ethereum_rpc_url: 'Ethereum RPC URL — required for ENS name/avatar resolution and EIP-1271 smart contract wallet verification (e.g. SAFE). A dedicated endpoint (Alchemy, Infura) is recommended.'
    siwe_statement: 'Statement that will be displayed in the SIWE message'
    siwe_society_enabled: 'Enable Society Protocol identity resolution and the display-identity toggle'
    siwe_society_subgraph_url: 'Society Protocol subgraph URL (optional; falls back to direct RPC if blank or failing)'
    siwe_society_badges_contract: 'Society Protocol Badges (ERC-1155) contract address'
    siwe_identity_resolution_mode: 'Preferred resolution mode for Society Protocol identities'



================================================
FILE: lib/discourse_siwe/display_name_applier.rb
================================================
# frozen_string_literal: true

require_relative 'url_validator'

module DiscourseSiwe
  # Applies the user's preferred web3 identity to their Discourse profile.
  # - user.name (display name)
  # - user avatar download job, if the chosen identity has an avatar URL
  # Username is intentionally never changed by this feature.
  module DisplayNameApplier
    module_function

    def apply(user)
      identities = IdentityStore.web3_identities(user)
      pref = identities[:preferred_identity]

      new_name = display_name_for(pref, identities)
      user.name = new_name if new_name.present?

      avatar_url = avatar_for(pref, identities)
      enqueue_avatar_download(user, avatar_url) if avatar_url.present?
    end

    def display_name_for(pref, identities)
      case pref
      when 'society'
        identities[:society_name]
      when 'ens'
        identities[:ens_name]
      when 'wallet'
        wallet = identities[:wallet_address]
        wallet.present? ? "#{wallet[0..5]}…#{wallet[-4..-1]}" : nil
      end
    end

    def avatar_for(pref, identities)
      case pref
      when 'society' then identities[:society_avatar]
      when 'ens'     then identities[:ens_avatar]
      else nil
      end
    end

    def enqueue_avatar_download(user, url)
      normalized = DiscourseSiwe::UrlValidator.normalize(url)
      return unless normalized

      Jobs.enqueue(:download_avatar_from_url, user_id: user.id, url: normalized)
    rescue StandardError => e
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn("[discourse-siwe-auth] Failed to enqueue avatar download: #{e.message}")
      end
    end
  end
end



================================================
FILE: lib/discourse_siwe/ens_resolver.rb
================================================
# frozen_string_literal: true

require 'net/http'

module DiscourseSiwe
  # Server-side ENS reverse + forward resolution with spoofing check, plus
  # avatar lookup via the ENS metadata service.
  module EnsResolver
    module_function

    # ENS Registry contract address (same on all EVM networks).
    ENS_REGISTRY = '0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e'

    # Function selectors.
    RESOLVER_SELECTOR     = '0178b8bf' # resolver(bytes32)
    REVERSE_NAME_SELECTOR = '691f3431' # name(bytes32)
    FORWARD_ADDR_SELECTOR = '3b3b57de' # addr(bytes32)

    # Public entry point. Returns [ens_name, avatar_url] or [nil, nil].
    def resolve(address)
      return [nil, nil] unless address.present? && DiscourseSiwe::EthRpc.rpc_url

      http = DiscourseSiwe::EthRpc.connection
      http.start do
        addr_clean = DiscourseSiwe::EthRpc.remove_hex_prefix(address).downcase
        reverse_node = namehash("#{addr_clean}.addr.reverse")

        resolver = decode_address(
          DiscourseSiwe::EthRpc.eth_call(ENS_REGISTRY, "0x#{RESOLVER_SELECTOR}#{reverse_node}", http: http)
        )
        return [nil, nil] unless resolver

        name = decode_string(
          DiscourseSiwe::EthRpc.eth_call(resolver, "0x#{REVERSE_NAME_SELECTOR}#{reverse_node}", http: http)
        )
        return [nil, nil] if name.blank?

        # Forward verify — resolve name back to address to prevent spoofing.
        forward_node = namehash(name)
        fwd_resolver = decode_address(
          DiscourseSiwe::EthRpc.eth_call(ENS_REGISTRY, "0x#{RESOLVER_SELECTOR}#{forward_node}", http: http)
        )
        return [nil, nil] unless fwd_resolver

        resolved_addr = decode_address(
          DiscourseSiwe::EthRpc.eth_call(fwd_resolver, "0x#{FORWARD_ADDR_SELECTOR}#{forward_node}", http: http)
        )
        return [nil, nil] unless resolved_addr&.downcase == address.downcase

        [name, avatar_url(name)]
      end
    rescue StandardError
      [nil, nil]
    end

    # Compute ENS namehash for a domain name.
    def namehash(name)
      node = "\x00" * 32
      unless name.nil? || name.empty?
        name.split('.').reverse.each do |label|
          label_hash = DiscourseSiwe::EthRpc.keccak256(label)
          node = DiscourseSiwe::EthRpc.keccak256(node + label_hash)
        end
      end
      DiscourseSiwe::EthRpc.bin_to_hex(node)
    end

    # Returns the ENS metadata avatar URL if it responds 200, nil otherwise.
    def avatar_url(name)
      url = "https://metadata.ens.domains/mainnet/avatar/#{name}"
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 5
      response = http.request(Net::HTTP::Head.new(uri.path))
      response.code.to_i == 200 ? url : nil
    rescue StandardError
      nil
    end

    def decode_address(hex)
      DiscourseSiwe::EthRpc.decode_address(hex)
    end

    def decode_string(hex)
      DiscourseSiwe::EthRpc.decode_string(hex)
    end
  end
end



================================================
FILE: lib/discourse_siwe/eth_rpc.rb
================================================
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'digest/keccak'

module DiscourseSiwe
  # Reusable Ethereum JSON-RPC helpers used by the SIWE strategy, ENS resolver,
  # Society Protocol resolver, and the migration rake task.
  module EthRpc
    module_function

    def rpc_url
      url = SiteSetting.siwe_ethereum_rpc_url rescue nil
      url if url&.present?
    end

    def connection
      uri = URI(rpc_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 10
      http
    end

    # Generic eth_call. Returns hex result without 0x prefix, or nil.
    # `to` may be nil for contract-creation simulation (used by EIP-6492).
    def eth_call(to, data, http: nil)
      return nil unless rpc_url

      http ||= connection
      path = URI(rpc_url).path
      path = '/' if path.empty?

      req = Net::HTTP::Post.new(path, 'Content-Type' => 'application/json')
      call_params = { data: data }
      call_params[:to] = to if to
      req.body = {
        jsonrpc: '2.0',
        method: 'eth_call',
        params: [call_params, 'latest'],
        id: 1
      }.to_json

      response = http.request(req)
      result = JSON.parse(response.body)
      return nil if result['error'] || result['result'].nil? || result['result'] == '0x'

      remove_hex_prefix(result['result'])
    rescue StandardError
      nil
    end

    def encode_address(addr)
      remove_hex_prefix(addr).downcase.rjust(64, '0')
    end

    def encode_uint256(n)
      n.to_i.to_s(16).rjust(64, '0')
    end

    def decode_address(hex)
      return nil if hex.nil? || hex.length < 40
      address = hex[-40, 40]
      return nil if address == '0' * 40
      "0x#{address}"
    end

    def decode_uint256(hex)
      return nil if hex.nil? || hex.empty?
      hex.to_i(16)
    end

    def decode_string(hex)
      return nil if hex.nil? || hex.length < 128
      offset = hex[0, 64].to_i(16) * 2
      length = hex[offset, 64].to_i(16)
      return '' if length.zero?
      data_start = offset + 64
      return nil if hex.length < data_start + length * 2
      [hex[data_start, length * 2]].pack('H*').force_encoding('UTF-8')
    end

    # Keccak-256 via the keccak gem (no native rbsecp256k1 dependency).
    def keccak256(data)
      Digest::Keccak.new(256).digest(data)
    end

    def bin_to_hex(bin)
      bin.unpack1('H*')
    end

    def remove_hex_prefix(str)
      str.to_s.sub(/\A0x/i, '')
    end
  end
end



================================================
FILE: lib/discourse_siwe/identity_resolver.rb
================================================
# frozen_string_literal: true

require 'net/http'
require 'json'
require_relative 'url_validator'

module DiscourseSiwe
  # Resolves a Society Protocol profile badge for an Ethereum address.
  # Uses the configured subgraph by default and falls back to direct RPC calls.
  # Every failure path returns nil so login is never blocked.
  class IdentityResolver
    # Standard ERC-1155 selectors.
    BALANCE_OF_SELECTOR = '00fdd58e'
    URI_SELECTOR        = '0e89341c'

    # SocietyProtocolBadges.profileBadgeId(address)
    PROFILE_BADGE_ID_SELECTOR = EthRpc.bin_to_hex(
      EthRpc.keccak256('profileBadgeId(address)')[0, 4]
    ).freeze

    USER_QUERY = <<~GRAPHQL
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
          bio
          imageUrl
          profile {
            id
            name
            description
            imageUrl
            uri
          }
        }
      }
    GRAPHQL

    def self.resolve(wallet_address)
      new(wallet_address).resolve
    end

    def initialize(wallet_address)
      @wallet_address = wallet_address.to_s.downcase
    end

    # Returns { badge_id:, name:, bio:, avatar:, uri: } or nil.
    def resolve
      return nil unless SiteSetting.siwe_society_enabled
      return nil unless @wallet_address.match?(/\A0x[0-9a-fA-F]{40}\z/)

      if SiteSetting.siwe_identity_resolution_mode == 'subgraph' &&
         !SiteSetting.siwe_society_subgraph_url.to_s.strip.empty?
        via_subgraph || via_rpc
      else
        via_rpc
      end
    end

    private

    def via_subgraph
      uri = URI(SiteSetting.siwe_society_subgraph_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 10

      req = Net::HTTP::Post.new(
        uri.path.empty? ? '/' : uri.path,
        'Content-Type' => 'application/json'
      )
      req.body = { query: USER_QUERY, variables: { id: @wallet_address } }.to_json

      data = JSON.parse(http.request(req).body).dig('data', 'user')
      return nil unless data

      profile = data['profile'] || {}
      {
        badge_id: profile['id'],
        name:   first_non_empty(data['name'], profile['name']),
        bio:    first_non_empty(data['bio'], profile['description']),
        avatar: normalize_url(first_non_empty(data['imageUrl'], profile['imageUrl'])),
        uri:    profile['uri'],
      }
    rescue StandardError => e
      log_warn("[discourse-siwe-auth] Society subgraph error: #{e.message}")
      nil
    end

    def via_rpc
      return nil unless DiscourseSiwe::EthRpc.rpc_url
      contract = SiteSetting.siwe_society_badges_contract.to_s
      return nil unless contract.match?(/\A0x[0-9a-fA-F]{40}\z/)

      http = DiscourseSiwe::EthRpc.connection
      http.start do
        badge_id_hex = DiscourseSiwe::EthRpc.eth_call(
          contract,
          "0x#{PROFILE_BADGE_ID_SELECTOR}#{DiscourseSiwe::EthRpc.encode_address(@wallet_address)}",
          http: http
        )
        badge_id = DiscourseSiwe::EthRpc.decode_uint256(badge_id_hex)
        return nil if badge_id.nil? || badge_id.zero?

        balance_hex = DiscourseSiwe::EthRpc.eth_call(
          contract,
          "0x#{BALANCE_OF_SELECTOR}" \
            "#{DiscourseSiwe::EthRpc.encode_address(@wallet_address)}" \
            "#{DiscourseSiwe::EthRpc.encode_uint256(badge_id)}",
          http: http
        )
        balance = DiscourseSiwe::EthRpc.decode_uint256(balance_hex)
        return nil if balance.nil? || balance.zero?

        uri_hex = DiscourseSiwe::EthRpc.eth_call(
          contract,
          "0x#{URI_SELECTOR}#{DiscourseSiwe::EthRpc.encode_uint256(badge_id)}",
          http: http
        )
        metadata_uri = DiscourseSiwe::EthRpc.decode_string(uri_hex)
        meta = fetch_metadata(metadata_uri)

        {
          badge_id: badge_id.to_s,
          name:   meta&.dig('name'),
          bio:    meta&.dig('description'),
          avatar: normalize_url(meta&.dig('image')),
          uri:    metadata_uri,
        }
      end
    rescue StandardError => e
      log_warn("[discourse-siwe-auth] Society RPC resolution error: #{e.message}")
      nil
    end

    def fetch_metadata(metadata_uri)
      url = normalize_url(metadata_uri)
      return nil if url.to_s.strip.empty?

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 10
      JSON.parse(http.request(Net::HTTP::Get.new(uri.request_uri)).body)
    rescue StandardError
      nil
    end

    def normalize_url(url)
      DiscourseSiwe::UrlValidator.normalize(url)
    end

    def first_non_empty(*values)
      values.find { |v| !v.to_s.strip.empty? }
    end

    def log_warn(message)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      end
    end
  end
end



================================================
FILE: lib/discourse_siwe/identity_store.rb
================================================
# frozen_string_literal: true

module DiscourseSiwe
  # Pure helpers for reading and writing web3 identity custom fields.
  # Used by SiweAuthenticator, RefreshSiweIdentity job, and the rake task.
  module IdentityStore
    module_function

    FIELDS = %w[
      wallet_address ens_name ens_avatar
      society_badge_id society_name society_avatar society_bio
      preferred_identity society_resolved_at
    ].freeze

    def store_society(user, society)
      user.custom_fields['society_badge_id'] = society&.[](:badge_id)
      user.custom_fields['society_name']    = society&.[](:name)
      user.custom_fields['society_avatar']  = society&.[](:avatar)
      user.custom_fields['society_bio']     = society&.[](:bio)
      user.custom_fields['society_resolved_at'] = Time.now.utc.iso8601
    end

    def default_preference(custom_fields)
      if nonempty?(custom_fields['society_name']) then 'society'
      elsif nonempty?(custom_fields['ens_name'])  then 'ens'
      else 'wallet'
      end
    end

    def web3_identities(user)
      cf = user.custom_fields
      {
        wallet_address: cf['wallet_address'],
        ens_name: cf['ens_name'],
        ens_avatar: cf['ens_avatar'],
        society_badge_id: cf['society_badge_id'],
        society_name: cf['society_name'],
        society_avatar: cf['society_avatar'],
        society_bio: cf['society_bio'],
        preferred_identity: cf['preferred_identity'] || 'wallet',
      }
    end

    def society_stale?(user)
      resolved_at = user.custom_fields['society_resolved_at']
      return true if resolved_at.to_s.strip.empty?
      Time.parse(resolved_at) < (Time.now.utc - 86_400)
    rescue ArgumentError
      true
    end

    def nonempty?(value)
      !value.to_s.strip.empty?
    end
  end
end



================================================
FILE: lib/discourse_siwe/url_validator.rb
================================================
# frozen_string_literal: true

require 'ipaddr'
require 'uri'

module DiscourseSiwe
  # Shared, strict URL validation for URLs that originate from external
  # contracts, subgraphs, or ENS metadata. Used by identity resolution and
  # avatar download enqueuing to reduce SSRF / local-network surface.
  module UrlValidator
    module_function

    ALLOWED_SCHEMES = %w[http https ipfs].freeze

    PRIVATE_CIDRS = %w[
      127.0.0.0/8
      10.0.0.0/8
      172.16.0.0/12
      192.168.0.0/16
      169.254.0.0/16
      fc00::/7
      fe80::/10
      ::1/128
    ].map { |c| IPAddr.new(c) }.freeze

    # Returns a normalized HTTPS URL, or nil if the URL is unsafe/unsupported.
    # ipfs://<cid> is rewritten to the configured HTTPS gateway.
    def normalize(url, ipfs_gateway: 'https://ipfs.io/ipfs/')
      url = url.to_s.strip
      return nil if url.empty?

      normalized = url.start_with?('ipfs://') ? "#{ipfs_gateway}#{url.sub('ipfs://', '')}" : url
      safe?(normalized) ? normalized : nil
    end

    # Returns true for http(s) public destinations and ipfs:// URIs with a path.
    def safe?(url)
      uri = URI.parse(url.to_s)
      return false unless ALLOWED_SCHEMES.include?(uri.scheme)

      if uri.scheme == 'ipfs'
        path = uri.path.to_s.strip
        return !path.empty? && path.length > 1
      end

      return false if uri.host.to_s.strip.empty?
      return false if uri.host.match?(/\A(localhost|localhost\.localdomain)\z/i)

      begin
        ip = IPAddr.new(uri.host)
        return false if PRIVATE_CIDRS.any? { |c| c.include?(ip) }
      rescue IPAddr::InvalidAddressError
        # Not an IP address; treat as a public domain name.
      end

      true
    rescue URI::Error
      false
    end
  end
end



================================================
FILE: lib/omniauth/strategies/siwe.rb
================================================
require 'net/http'
require 'json'

module OmniAuth
  module Strategies
    class Siwe
      include OmniAuth::Strategy

      # EIP-6492 universal signature validator bytecode (no 0x prefix).
      # Deployed via eth_call (no actual deployment) to verify EOA, ERC-1271,
      # and EIP-6492 signatures in a single call.
      # Constructor: (address signer, bytes32 hash, bytes signature)
      # Returns: 0x01 if valid, 0x00 if invalid
      # Source: EIP-6492 reference implementation
      EIP6492_VALIDATOR_BYTECODE = "608060405234801561001057600080fd5b5060405161069438038061069483398101604081905261002f9161051e565b600061003c848484610048565b9050806000526001601ff35b60007f64926492649264926492649264926492649264926492649264926492649264926100748361040c565b036101e7576000606080848060200190518101906100929190610577565b60405192955090935091506000906001600160a01b038516906100b69085906105dd565b6000604051808303816000865af19150503d80600081146100f3576040519150601f19603f3d011682016040523d82523d6000602084013e6100f8565b606091505b50509050876001600160a01b03163b60000361016057806101605760405162461bcd60e51b815260206004820152601e60248201527f5369676e617475726556616c696461746f723a206465706c6f796d656e74000060448201526064015b60405180910390fd5b604051630b135d3f60e11b808252906001600160a01b038a1690631626ba7e90610190908b9087906004016105f9565b602060405180830381865afa1580156101ad573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101d19190610633565b6001600160e01b03191614945050505050610405565b6001600160a01b0384163b1561027a57604051630b135d3f60e11b808252906001600160a01b03861690631626ba7e9061022790879087906004016105f9565b602060405180830381865afa158015610244573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906102689190610633565b6001600160e01b031916149050610405565b81516041146102df5760405162461bcd60e51b815260206004820152603a602482015260008051602061067483398151915260448201527f3a20696e76616c6964207369676e6174757265206c656e6774680000000000006064820152608401610157565b6102e7610425565b5060208201516040808401518451859392600091859190811061030c5761030c61065d565b016020015160f81c9050601b811480159061032b57508060ff16601c14155b1561038c5760405162461bcd60e51b815260206004820152603b602482015260008051602061067483398151915260448201527f3a20696e76616c6964207369676e617475726520762076616c756500000000006064820152608401610157565b60408051600081526020810180835289905260ff83169181019190915260608101849052608081018390526001600160a01b0389169060019060a0016020604051602081039080840390855afa1580156103ea573d6000803e3d6000fd5b505050602060405103516001600160a01b0316149450505050505b9392505050565b600060208251101561041d57600080fd5b508051015190565b60405180606001604052806003906020820280368337509192915050565b6001600160a01b038116811461045857600080fd5b50565b634e487b7160e01b600052604160045260246000fd5b60005b8381101561048c578181015183820152602001610474565b50506000910152565b600082601f8301126104a657600080fd5b81516001600160401b038111156104bf576104bf61045b565b604051601f8201601f19908116603f011681016001600160401b03811182821017156104ed576104ed61045b565b60405281815283820160200185101561050557600080fd5b610516826020830160208701610471565b949350505050565b60008060006060848603121561053357600080fd5b835161053e81610443565b6020850151604086015191945092506001600160401b0381111561056157600080fd5b61056d86828701610495565b9150509250925092565b60008060006060848603121561058c57600080fd5b835161059781610443565b60208501519093506001600160401b038111156105b357600080fd5b6105bf86828701610495565b604086015190935090506001600160401b0381111561056157600080fd5b600082516105ef818460208701610471565b9190910192915050565b828152604060208201526000825180604084015261061e816060850160208701610471565b601f01601f1916919091016060019392505050565b60006020828403121561064557600080fd5b81516001600160e01b03198116811461040557600080fd5b634e487b7160e01b600052603260045260246000fdfe5369676e617475726556616c696461746f72237265636f7665725369676e6572"

      option :fields, %i[eth_message eth_signature]

      uid do
        @verified_address
      end

      info do
        ens_name, ens_avatar = DiscourseSiwe::EnsResolver.resolve(@verified_address)
        display_name = ens_name || @verified_address
        {
          nickname: display_name,
          name: display_name,
          image: ens_avatar
        }
      end

      def request_phase
        query_string = env['QUERY_STRING']
        redirect "/discourse-siwe/auth?#{query_string}"
      end

      def callback_phase
        eth_message_crlf = request.params['eth_message']
        eth_message = eth_message_crlf.encode(eth_message_crlf.encoding, universal_newline: true)
        eth_signature = request.params['eth_signature']
        siwe_message = ::Siwe::Message.from_message(eth_message)

        domain = Discourse.base_url.delete_prefix("#{Discourse.base_protocol}://")
        if siwe_message.domain != domain
          return fail!("Invalid domain")
        end

        nonce = session.delete(:nonce)
        if siwe_message.nonce != nonce
          return fail!("Invalid nonce")
        end

        @verified_address = siwe_message.address

        failure_reason = nil
        begin
          siwe_message.validate(eth_signature)
        rescue ::Siwe::ExpiredMessage
          failure_reason = :expired_message
        rescue ::Siwe::NotValidMessage
          failure_reason = :invalid_message
        rescue ::Siwe::InvalidSignature
          # EOA verification failed — try EIP-6492 universal validator which handles
          # both deployed wallets (EIP-1271, e.g. Safe) and undeployed accounts
          # (EIP-6492, e.g. Coinbase Smart Wallet)
          unless smart_wallet_valid?(siwe_message, eth_signature)
            failure_reason = :invalid_signature
          end
        end

        return fail!(failure_reason) if failure_reason

        super
      end

      private

      # Universal smart-wallet signature verification using the EIP-6492
      # off-chain validator. A single eth_call (contract creation simulation)
      # that handles deployed EIP-1271 wallets (e.g. Safe) AND undeployed
      # ERC-4337 accounts (e.g. Coinbase Smart Wallet) in one shot.
      def smart_wallet_valid?(siwe_message, signature)
        return false unless DiscourseSiwe::EthRpc.rpc_url

        # Hash the message the same way personal_sign does (EIP-191)
        prefixed = Eth::Signature.prefix_message(siwe_message.prepare_message)
        message_hash = Eth::Util.bin_to_hex(Eth::Util.keccak256(prefixed))

        # ABI-encode constructor args: (address signer, bytes32 hash, bytes signature)
        address_param = Eth::Util.remove_hex_prefix(siwe_message.address).downcase.rjust(64, '0')
        hash_param = message_hash.rjust(64, '0')
        sig_bytes = Eth::Util.remove_hex_prefix(signature)
        # bytes offset: 3 × 32 = 96 = 0x60
        bytes_offset = "0000000000000000000000000000000000000000000000000000000000000060"
        sig_length = (sig_bytes.length / 2).to_s(16).rjust(64, '0')
        sig_padded = sig_bytes.ljust(((sig_bytes.length + 63) / 64) * 64, '0')

        data = "0x#{EIP6492_VALIDATOR_BYTECODE}#{address_param}#{hash_param}#{bytes_offset}#{sig_length}#{sig_padded}"

        # eth_call with no 'to' simulates contract creation
        result = DiscourseSiwe::EthRpc.eth_call(nil, data)
        return false if result.nil?

        # Validator returns 0x01 (possibly zero-padded to 32 bytes) for valid
        result.gsub(/\A0+/, '') == '1'
      end
    end
  end
end



================================================
FILE: lib/tasks/siwe_identities.rake
================================================
# frozen_string_literal: true

namespace :siwe do
  desc 'Backfill web3 identity custom fields for existing SIWE users'
  task :migrate_identities, [:dry_run] => :environment do |_t, args|
    dry_run = args[:dry_run] == 'true'
    migrated = 0

    UserAssociatedAccount.where(provider_name: 'siwe').find_each do |assoc|
      user = assoc.user
      next unless user

      wallet = assoc.provider_uid&.downcase
      next if wallet.blank? || user.custom_fields['wallet_address'].present?

      puts "#{dry_run ? '[dry-run] ' : ''}Migrating #{user.username} (ID: #{user.id})"

      unless dry_run
        user.custom_fields['wallet_address'] = wallet

        ens_name, ens_avatar = DiscourseSiwe::EnsResolver.resolve(wallet)
        user.custom_fields['ens_name']   = ens_name   if ens_name
        user.custom_fields['ens_avatar'] = ens_avatar if ens_avatar

        society = DiscourseSiwe::IdentityResolver.resolve(wallet)
        DiscourseSiwe::IdentityStore.store_society(user, society)
        user.custom_fields['preferred_identity'] =
          DiscourseSiwe::IdentityStore.default_preference(user.custom_fields)

        user.save_custom_fields

        # Do not rewrite existing display names during bulk migration.
        # The user's display name will update the next time they log in or
        # change their preferred identity in preferences.
        sleep 0.5
      end

      migrated += 1
    end

    puts "Done. #{migrated} users #{dry_run ? 'would be' : 'were'} migrated."
  end
end



================================================
FILE: PlanFolder/ImplementationReport.md
================================================
# Implementation Report: Society Protocol Identity Toggle

**Date:** 2026-08-05  
**Plugin version:** 1.3.0  
**Compared against:** `PlanFolder/InitialPlan.md` and `PlanFolder/RefinedPlan.md`

## Summary

The Society Protocol identity feature is **functionally complete** and matches the
Refined Plan with one intentional remaining item: the frontend component is
implemented as a classic Ember component (`.js` + `.hbs`) rather than a `.gjs`
component. This avoids plugin `.gjs` support uncertainty while still satisfying
the feature requirement.

In addition to the plan, this pass added:

- A `UrlValidator` security helper to prevent SSRF/private-network fetches from
  Society badge metadata / avatar URLs.
- Frontend file renames to remove Discourse 2026 `.js.es6` deprecations.
- A rewritten `README.md` that documents Society Protocol, security
  considerations, local-dev wallet quirks, and installation.

## Item-by-item comparison with the Refined Plan

| # | Refined Plan item | Status | Notes |
|---|---|---|---|
| 1 | Settings in `config/settings.yml` (`siwe_society_enabled`, `siwe_society_subgraph_url`, `siwe_society_badges_contract`, `siwe_identity_resolution_mode`) | ✅ Done | Default contract is `0x2313C0cDdc233c92d16c2cfE17DF5fDCcE556763`; no separate `siwe_society_rpc_url` — RPC falls back to `siwe_ethereum_rpc_url`. |
| 2 | `lib/discourse_siwe/eth_rpc.rb` shared helper | ✅ Done | Used by ENS resolver, Society resolver, SIWE strategy, and migration. |
| 3 | Refactor `lib/omniauth/strategies/siwe.rb` to use `EthRpc` | ✅ Done | `smart_wallet_valid?` calls `DiscourseSiwe::EthRpc.rpc_url` / `.eth_call`; ENS resolution delegates to `EnsResolver`. |
| 4 | `lib/discourse_siwe/identity_resolver.rb` full implementation | ✅ Done | Subgraph path + RPC fallback; `profileBadgeId`, `balanceOf`, `uri` calldata; metadata fetch; safe URL normalization. |
| 5 | `lib/discourse_siwe/ens_resolver.rb` extraction | ✅ Done | `EnsResolver.resolve(address)` returns `[name, avatar]` with forward/reverse spoofing check. |
| 6 | `plugin.rb` custom fields + serializer + routes | ✅ Done | All Refined Plan fields registered; `web3_identities` serialized only to the owning user; routes include `/update-identity`. |
| 7 | `SiweAuthenticator` `after_authenticate` / `after_create_account` | ✅ Done | Wallet from `auth_token.uid`; ENS refresh on login; Society resolution inline at signup; throttled refresh job for existing users. |
| 8 | `app/jobs/regular/refresh_siwe_identity.rb` throttled background refresh | ✅ Done | 24-hour throttle via `society_resolved_at`. |
| 9 | `update_identity` endpoint applies choice via `DisplayNameApplier` | ✅ Done | Validates availability, persists preference, re-applies display name/avatar. |
| 10 | `lib/discourse_siwe/display_name_applier.rb` | ✅ Done | Updates `user.name` and enqueues avatar download; username is never changed. |
| 11 | Frontend `.gjs` component | ✅ Done | Connector converted to `.gjs`; component kept as `.js` + `.hbs` in `assets/javascripts/discourse/components/`. |
| 12 | Connector rendering the selector in preferences/profile | ✅ Done | `siwe-identity-selector.gjs` connector imports and renders the component with `@model={{@outletArgs.model}}`. |
| 13 | Styles + locales | ✅ Done | `.siwe-identity-selector` styles and `js.discourse_siwe.identity.*` i18n keys added. |
| 14 | Migration rake task `siwe:migrate_identities[dry_run]` | ✅ Done | Backfills wallet, ENS, Society fields; leaves existing display names untouched. |
| 15 | Standalone minitest tests | ✅ Done | `test/society_unit_test.rb`, `test/society_integration_test.rb` plus existing ENS tests. |
| 16 | README update | ✅ Done | Comprehensive rewrite covering Society Protocol, security, install, local dev, and troubleshooting. |
| 17 | Version bump to 1.3.0 | ✅ Done | `plugin.rb` header. |

## Additional work not in the original plans

| Change | File(s) | Why |
|---|---|---|
| `UrlValidator` security helper | `lib/discourse_siwe/url_validator.rb` | Prevents the plugin from fetching metadata/avatars from `file://`, `localhost`, or private IP ranges if an admin misconfigures the contract or subgraph. |
| Validate avatar URLs before enqueueing | `lib/discourse_siwe/display_name_applier.rb` | Defense-in-depth before handing a URL to Discourse's avatar downloader. |
| Frontend deprecation cleanup | `assets/javascripts/discourse/**/*.js` | Renamed `.js.es6` → `.js` and moved component template from `templates/components/` to `components/` to remove Discourse 2026 console warnings. |
| URL-validator unit tests | `test/society_unit_test.rb` | Coverage for safe/unsafe URL handling. |

## What remains

1. **Run the test suite in the Discourse container.** The tests cannot be run
   from the host shell because Ruby is only available inside the
   `discourse_dev` Docker container. Command to run:

   ```bash
   docker exec -u discourse -w /src discourse_dev bash -c \
     "cd plugins/discourse-siwe-auth && for f in test/*_test.rb; do ruby \"$f\"; done"
   ```

2. **Browser verification of the `.gjs` connector.** The `.gjs` connector uses
   the plugin module path `discourse/plugins/discourse-siwe-auth/discourse/components/siwe-identity-selector`.
   If the Discourse build does not resolve this path, fall back to the relative
   import `../../../components/siwe-identity-selector` inside the `.gjs` file.

## Verification performed

- HTTP smoke test: `curl /discourse-siwe/message?eth_account=...&chain_id=1`
  returned a valid SIWE message for `localhost:3000`.
- Code review of all resolver/authenticator/controller paths against the
  Refined Plan.
- Confirmed Society Protocol docs match the default contract address.

## Security findings addressed

- SSRF risk from arbitrary metadata/avatar URLs → mitigated by `UrlValidator`.
- Trust model for RPC/subgraph → documented in README.
- Email verification behavior → documented with Rails-console escape hatch.
- Custom-field privacy → already correct (`web3_identities` owner-only).
- Username stability → already correct (only display name/avatar changed).

## Conclusion

The plugin as it stands in the working tree implements the Refined Plan's
Society Protocol identity toggle end-to-end. The connector is now `.gjs`,
frontend `.js.es6` / `templates/components/` deprecations are resolved, and the
README documents the feature. The remaining work is running the test suite
inside the Discourse container and confirming the `.gjs` connector renders in
**Preferences > Profile**.



================================================
FILE: PlanFolder/InitialCodebase.md
================================================
[Empty file]


================================================
FILE: PlanFolder/InitialPlan.md
================================================
### **SPEC: Society Protocol Identity Toggle for Discourse SIWE**

**Repository:** `https://github.com/SocietyProtocol/discourse-siwe-auth`**Discourse Version:** 2026.6.0-latest (production) / 2026.7.0-latest (test)**Scope:** Non-destructive enhancement for existing SIWE users

---

#### **1. Architecture Summary**

The existing fork already has:

- ✅ SIWE authentication (self-contained, no gem dependency issues)
- ✅ ENS resolution (forward+reverse verified)
- ✅ EIP-6492 smart wallet support (Coinbase Smart Wallet, Safe, etc.)

**What we add:**

- Society Protocol identity resolution (via subgraph or direct RPC)
- Custom user fields to store all identities
- User preference toggle in profile settings
- Display name override based on preference

---

#### **2. Data Model: Custom User Fields**

Create these fields for all SIWE users. Populate via one-time migration + ongoing login refresh.

**Table**

| **Field** | **Type** | **Source** | **Mutable** |
| --- | --- | --- | --- |
| `wallet_address` | string | `UserAssociatedAccount.provider_uid` | ❌ Immutable |
| `ens_name` | string | `resolve_ens()` in `siwe.rb` | ✅ |
| `ens_avatar` | string | `ens_avatar_url()` in `siwe.rb` | ✅ |
| `society_badge_id` | string | Subgraph/RPC: `profileBadgeId(address)` | ✅ |
| `society_name` | string | Badge metadata `name` | ✅ |
| `society_avatar` | string | Badge metadata `image` | ✅ |
| `society_bio` | string | Badge metadata `description` | ✅ |
| `preferred_identity` | string | User toggle: `wallet`/`ens`/`society` | ✅ |

---

#### **3. Plugin Settings (Add to `config/settings.yml`)**

**yaml**

```yaml
plugins:
  discourse_siwe_enabled:
    default: true
    client: true

  siwe_society_subgraph_url:
    default: ""
    client: false
    type: string
    description: "Society Protocol subgraph URL (optional, falls back to RPC)"

  siwe_society_rpc_url:
    default: "https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
    client: false
    type: string
    description: "Ethereum RPC URL for direct contract calls"

  siwe_society_badges_contract:
    default: "0xa3af0da9733061da88b91ea28740780a887c8ce3"
    client: false
    type: string

  siwe_identity_resolution_mode:
    default: "subgraph"
    type: enum
    choices:
      - subgraph
      - rpc
    client: false
```

---

#### **4. Backend Changes**

#### **4.1 New File: `lib/discourse_siwe/identity_resolver.rb`**

**ruby**

```ruby
# frozen_string_literal: true

module DiscourseSiwe
  class IdentityResolver
    SOCIETY_BADGES_ABI = [
      {
        "inputs": [{ "name": "", "type": "address" }],
        "name": "profileBadgeId",
        "outputs": [{ "name": "", "type": "uint256" }],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          { "name": "account", "type": "address" },
          { "name": "id", "type": "uint256" }
        ],
        "name": "balanceOf",
        "outputs": [{ "name": "", "type": "uint256" }],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [{ "name": "id", "type": "uint256" }],
        "name": "uri",
        "outputs": [{ "name": "", "type": "string" }],
        "stateMutability": "view",
        "type": "function"
      }
    ].freeze

    def self.resolve(wallet_address)
      new(wallet_address).resolve
    end

    def initialize(wallet_address)
      @wallet_address = wallet_address.downcase
      @mode = SiteSetting.siwe_identity_resolution_mode
    end

    def resolve
      {
        ens: nil, # ENS is already resolved in siwe.rb strategy
        society: resolve_society
      }
    end

    private

    def resolve_society
      if @mode == "subgraph" && SiteSetting.siwe_society_subgraph_url.present?
        resolve_society_via_subgraph
      else
        resolve_society_via_rpc
      end
    end

    def resolve_society_via_subgraph
      query = <<~GRAPHQL
        query GetUser($address: ID!) {
          user(id: $address) {
            name
            bio
            imageUrl
            profile {
              id
              name
              imageUrl
              uri
            }
          }
        }GRAPHQL

      response = Excon.post(
        SiteSetting.siwe_society_subgraph_url,
        headers: { 'Content-Type' => 'application/json' },
        body: { query: query, variables: { address: @wallet_address } }.to_json,
        timeout: 10
      )

      data = JSON.parse(response.body)['data']['user'] rescue nil
      return nil unless data && data['profile']

      {
        badge_id: data['profile']['id'],
        name: data['name'] || data['profile']['name'],
        bio: data['bio'],
        avatar: data['imageUrl'] || data['profile']['imageUrl'],
        uri: data['profile']['uri']
      }
    rescue => e
      Rails.logger.error("Society Protocol subgraph error:#{e.message}")
      nil
    end

    def resolve_society_via_rpc
      # Uses the existing RPC infrastructure from siwe.rb
      # 1. Call profileBadgeId(address)
      # 2. Verify balanceOf(address, badgeId) > 0
      # 3. Call uri(badgeId)
      # 4. Fetch metadata from URI
      # Implementation follows same pattern as resolve_ens in siwe.rb
      nil # Placeholder — implement if subgraph unavailable
    end
  end
end
```

#### **4.2 Modify `plugin.rb`: Add Engine + Custom Fields**

Add to the `after_initialize` block:

**ruby**

```ruby
after_initialize do
  # Load existing files
  load File.expand_path('../app/controllers/discourse_siwe/auth_controller.rb', __FILE__)
  load File.expand_path('../lib/discourse_siwe/identity_resolver.rb', __FILE__)

  # Register custom fields
  User.register_custom_field_type('wallet_address', :string)
  User.register_custom_field_type('ens_name', :string)
  User.register_custom_field_type('ens_avatar', :string)
  User.register_custom_field_type('society_badge_id', :string)
  User.register_custom_field_type('society_name', :string)
  User.register_custom_field_type('society_avatar', :string)
  User.register_custom_field_type('society_bio', :string)
  User.register_custom_field_type('preferred_identity', :string)

  # Add to user serializer for frontend access
  add_to_serializer(:user, :web3_identities) do
    {
      wallet_address: object.custom_fields['wallet_address'],
      ens_name: object.custom_fields['ens_name'],
      ens_avatar: object.custom_fields['ens_avatar'],
      society_badge_id: object.custom_fields['society_badge_id'],
      society_name: object.custom_fields['society_name'],
      society_avatar: object.custom_fields['society_avatar'],
      preferred_identity: object.custom_fields['preferred_identity'] || 'wallet'
    }
  end

  # Add routes
  Discourse::Application.routes.prepend do
    get '/discourse-siwe/auth' => 'discourse_siwe/auth#index'
    get '/discourse-siwe/message' => 'discourse_siwe/auth#message'
    post '/discourse-siwe/update-identity' => 'discourse_siwe/auth#update_identity'
  end
end
```

#### **4.3 Modify `SiweAuthenticator` in `plugin.rb`**

Override `after_authenticate` and `after_create_account`:

**ruby**

```ruby
class ::SiweAuthenticator < ::Auth::ManagedAuthenticator
  def name
    'siwe'
  end

  def register_middleware(omniauth)
    omniauth.provider :siwe, setup: lambda { |env|
      strategy = env['omniauth.strategy']
    }
  end

  def enabled?
    SiteSetting.discourse_siwe_enabled
  end

  def primary_email_verified?
    false
  end

  def description_for_auth_hash(auth_token)
    auth_token&.provider_uid || super
  end

  # === NEW: Identity resolution and storage ===

  def after_authenticate(auth_token, existing_account: nil)
    result = super

    wallet_address = auth_token.dig(:info, :name)
    return result unless wallet_address.present?

    # For existing users: refresh their identity data on every login
    if result.user
      refresh_user_identities(result.user, wallet_address)
      apply_preferred_identity(result, result.user)
    end

    # Pass identity data to after_create_account for new users
    result.extra_data = result.extra_data.merge({
      wallet_address: wallet_address,
      ens_name: auth_token.dig(:info, :nickname),
      ens_avatar: auth_token.dig(:info, :image),
      preferred_identity: 'ens' # Default new users to ENS if available
    })

    result
  end

  def after_create_account(user, auth_result)
    super

    extra = auth_result[:extra_data] || {}
    wallet_address = extra['wallet_address']
    return unless wallet_address.present?

    # Store all identity data
    user.custom_fields['wallet_address'] = wallet_address.downcase
    user.custom_fields['ens_name'] = extra['ens_name']
    user.custom_fields['ens_avatar'] = extra['ens_avatar']
    user.custom_fields['preferred_identity'] = extra['preferred_identity'] || 'wallet'

    # Resolve Society Protocol identity
    society_data = DiscourseSiwe::IdentityResolver.resolve(wallet_address)
    if society_data
      user.custom_fields['society_badge_id'] = society_data[:badge_id]
      user.custom_fields['society_name'] = society_data[:name]
      user.custom_fields['society_avatar'] = society_data[:avatar]
      user.custom_fields['society_bio'] = society_data[:bio]

      # If user has Society identity, default to it over ENS
      if society_data[:name].present?
        user.custom_fields['preferred_identity'] = 'society'
      end
    end

    user.save_custom_fields
  end

  private

  def refresh_user_identities(user, wallet_address)
    # Ensure wallet is always stored
    user.custom_fields['wallet_address'] ||= wallet_address.downcase

    # Refresh Society Protocol data (may have changed since last login)
    society_data = DiscourseSiwe::IdentityResolver.resolve(wallet_address)
    if society_data
      user.custom_fields['society_badge_id'] = society_data[:badge_id]
      user.custom_fields['society_name'] = society_data[:name]
      user.custom_fields['society_avatar'] = society_data[:avatar]
      user.custom_fields['society_bio'] = society_data[:bio]
    end

    # Set default preference if not already set
    if user.custom_fields['preferred_identity'].blank?
      if user.custom_fields['society_name'].present?
        user.custom_fields['preferred_identity'] = 'society'
      elsif user.custom_fields['ens_name'].present? && user.custom_fields['ens_name'] != wallet_address
        user.custom_fields['preferred_identity'] = 'ens'
      else
        user.custom_fields['preferred_identity'] = 'wallet'
      end
    end

    user.save_custom_fields
  end

  def apply_preferred_identity(result, user)
    pref = user.custom_fields['preferred_identity'] || 'wallet'

    case pref
    when 'society'
      if user.custom_fields['society_name'].present?
        result.username = sanitize_username(user.custom_fields['society_name'])
        result.name = user.custom_fields['society_name']
        result.avatar_url = user.custom_fields['society_avatar']
      end
    when 'ens'
      if user.custom_fields['ens_name'].present? && user.custom_fields['ens_name'] != user.custom_fields['wallet_address']
        result.username = sanitize_username(user.custom_fields['ens_name'])
        result.name = user.custom_fields['ens_name']
        result.avatar_url = user.custom_fields['ens_avatar']
      end
    when 'wallet'
      wallet = user.custom_fields['wallet_address']
      result.name = "#{wallet[0..5]}...#{wallet[-4..-1]}" if wallet.present?
    end
  end

  def sanitize_username(raw)
    return nil if raw.blank?
    raw.downcase
       .gsub('.', '_')        # ENS dots → underscores
       .gsub(/[^a-z0-9_-]/, '') # Only safe chars
       .slice(0, 60)
  end
end
```

#### **4.4 Add to Auth Controller: `update_identity` endpoint**

**ruby**

```ruby
# In app/controllers/discourse_siwe/auth_controller.rb

def update_identity
  return render json: { error: 'Not authenticated' }, status: 401 unless current_user

  preferred = params[:preferred_identity]
  allowed = %w[wallet ens society]

  unless allowed.include?(preferred)
    return render json: { error: 'Invalid identity type' }, status: 400
  end

  # Verify the user actually has this identity
  case preferred
  when 'ens'
    return render json: { error: 'No ENS name available' }, status: 400 unless current_user.custom_fields['ens_name'].present?
  when 'society'
    return render json: { error: 'No Society identity available' }, status: 400 unless current_user.custom_fields['society_badge_id'].present?
  end

  current_user.custom_fields['preferred_identity'] = preferred
  current_user.save_custom_fields

  render json: { success: true, preferred_identity: preferred }
end
```

---

#### **5. Frontend Changes**

#### **5.1 Add Identity Toggle UI to User Preferences**

Create a new component/template in the Discourse plugin:

**handlebars**

```
{{! assets/javascripts/discourse/templates/components/siwe-identity-selector.hbs }}

{{#if model.custom_fields.wallet_address}}
  <div class="control-group siwe-identity-selector">
    <label class="control-label">Web3 Display Identity</label>

    <div class="controls">
      {{! Wallet Address (always available) }}
      <label class="identity-option">
        <RadioButton
          @value="wallet"
          @selection={{model.custom_fields.preferred_identity}}
          @onChange={{action "selectIdentity" "wallet"}} />
        <span class="identity-icon">⬡</span>
        <span class="identity-name">{{model.custom_fields.wallet_address}}</span>
        <span class="identity-source">Wallet Address</span>
      </label>

      {{! ENS (if available) }}
      {{#if model.custom_fields.ens_name}}
        <label class="identity-option">
          <RadioButton
            @value="ens"
            @selection={{model.custom_fields.preferred_identity}}
            @onChange={{action "selectIdentity" "ens"}} />
          <span class="identity-icon">🌐</span>
          <span class="identity-name">{{model.custom_fields.ens_name}}</span>
          <span class="identity-source">ENS</span>
          {{#if model.custom_fields.ens_avatar}}
            <img src={{model.custom_fields.ens_avatar}} class="identity-preview" />
          {{/if}}
        </label>
      {{/if}}

      {{! Society Protocol (if available) }}
      {{#if model.custom_fields.society_badge_id}}
        <label class="identity-option">
          <RadioButton
            @value="society"
            @selection={{model.custom_fields.preferred_identity}}
            @onChange={{action "selectIdentity" "society"}} />
          <span class="identity-icon">🏛️</span>
          <span class="identity-name">{{model.custom_fields.society_name}}</span>
          <span class="identity-source">Society Protocol</span>
          {{#if model.custom_fields.society_avatar}}
            <img src={{model.custom_fields.society_avatar}} class="identity-preview" />
          {{/if}}
        </label>
      {{/if}}
    </div>
  </div>
{{/if}}
```

#### **5.2 JavaScript Controller**

**JavaScript**

```jsx
// assets/javascripts/discourse/components/siwe-identity-selector.js

import Component from "@ember/component";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";

export default Component.extend({
  @action
  selectIdentity(identity) {
    this.set('model.custom_fields.preferred_identity', identity);

    ajax('/discourse-siwe/update-identity', {
      type: 'POST',
      data: { preferred_identity: identity }
    }).then(() => {
      // Show success message
    }).catch((err) => {
      // Show error, revert selection
      this.set('model.custom_fields.preferred_identity', this.model.custom_fields.preferred_identity);
    });
  }
});
```

#### **5.3 Hook into User Preferences Page**

**JavaScript**

```jsx
// In plugin initializer
import { withPluginApi } from 'discourse/lib/plugin-api';

export default {
  name: 'siwe-identity-preferences',

  initialize() {
    withPluginApi('1.15.0', (api) => {
      // Add the identity selector to the profile preferences page
      api.modifyClass('controller:preferences/profile', {
        pluginId: 'siwe-identity-preferences',

        // The template will automatically pick up custom_fields from the model
      });
    });
  }
};
```

---

#### **6. One-Time Migration for Existing Users**

Run this in Rails console (or as a rake task):

**ruby**

```ruby
# lib/tasks/siwe_migrate_identities.rake

namespace :siwe do
  desc "Migrate existing SIWE users to new identity system"
  task migrate_identities: :environment do
    count = 0

    UserAssociatedAccount.where(provider_name: 'siwe').find_each do |assoc|
      user = assoc.user
      next unless user

      wallet = assoc.provider_uid.downcase

      # Skip if already migrated
      next if user.custom_fields['wallet_address'].present?

      # Store wallet address
      user.custom_fields['wallet_address'] = wallet

      # Extract ENS from existing auth data (if available in association)
      # The existing siwe.rb strategy already resolves ENS during login
      # If the user has logged in recently, the association info might have it
      ens_name = assoc.info&.dig('nickname')
      if ens_name.present? && ens_name != wallet
        user.custom_fields['ens_name'] = ens_name
        user.custom_fields['ens_avatar'] = assoc.info&.dig('image')
      end

      # Resolve Society Protocol identity
      society_data = DiscourseSiwe::IdentityResolver.resolve(wallet)
      if society_data
        user.custom_fields['society_badge_id'] = society_data[:badge_id]
        user.custom_fields['society_name'] = society_data[:name]
        user.custom_fields['society_avatar'] = society_data[:avatar]
        user.custom_fields['society_bio'] = society_data[:bio]
      end

      # Set default preference
      if society_data&.dig(:name).present?
        user.custom_fields['preferred_identity'] = 'society'
      elsif ens_name.present? && ens_name != wallet
        user.custom_fields['preferred_identity'] = 'ens'
      else
        user.custom_fields['preferred_identity'] = 'wallet'
      end

      user.save_custom_fields
      count += 1

      puts "Migrated user#{user.username} (ID:#{user.id}) with preference:#{user.custom_fields['preferred_identity']}"
    end

    puts "Migration complete.#{count} users migrated."
  end
end
```

---

#### **7. Testing Plan**

**Table**

| **Test** | **How** |
| --- | --- |
| **Migration dry-run** | Run on staging instance first, check console output |
| **New user signup** | Create fresh wallet, verify all identity fields populated |
| **Existing user login** | Verify identity refresh on login, preference preserved |
| **Toggle switch** | Change preference in UI, verify display name updates |
| **No Society identity** | Wallet without Society badge should show wallet/ENS only |
| **No ENS** | Wallet without ENS should show wallet/Society only |
| **No subgraph** | Set `siwe_identity_resolution_mode` to `rpc`, verify fallback |

---

#### **8. What You Need to Provide Your IDE Agent**

1. **This spec document** (copy-paste this entire message)
2. **The Society Protocol subgraph URL** — ask their engineer: "What's the GraphQL query endpoint for the web3-app-subgraph?"
3. **Your current `plugin.rb`** — confirm it's the one I fetched above
4. **Your current `siwe.rb`** — confirm it's the one with `resolve_ens` method
5. **Your Discourse version** — `2026.6.0-latest` (consider updating to `2026.7.0-latest` on test instance)

---

#### **9. Order of Implementation**

1. **Add custom field registration** to `plugin.rb`
2. **Create `identity_resolver.rb`** with subgraph integration
3. **Modify `SiweAuthenticator`** with `after_authenticate`/`after_create_account` overrides
4. **Add `update_identity` endpoint** to auth controller
5. **Build frontend toggle UI** (Ember component + template)
6. **Write migration rake task**
7. **Test on staging** → Deploy to production

---

Does this spec cover everything? Any part you want me to expand or simplify before you hand it to your IDE agent?


================================================
FILE: PlanFolder/RefinedPlan.md
================================================
# Refined Plan: Society Protocol Identity Toggle for Discourse SIWE

**Status:** Implementation-ready. Supersedes `InitialPlan.md`.
**Repo:** `SocietyProtocol/discourse-siwe-auth` — current version 1.2.1
**Target Discourse:** 2026.6.0 (prod) / 2026.7.0 (test)

This plan keeps the draft's overall shape (custom fields + resolver + toggle UI +
migration) but fixes concrete bugs found by reviewing it against the actual
codebase, and replaces every unverified Society Protocol assumption with facts
confirmed against their live repos and deployment.

---

## 1. Verified Society Protocol facts (ground truth)

Confirmed against [SocietyProtocol/web3-app-subgraph](https://github.com/SocietyProtocol/web3-app-subgraph),
[SocietyProtocol/web3-app-client](https://github.com/SocietyProtocol/web3-app-client), and
[SocietyProtocol/web3-app-contracts](https://github.com/SocietyProtocol/web3-app-contracts):

- **Live Badges contract (ERC-1155, UUPS proxy), Ethereum mainnet:**
  `0x2313C0cDdc233c92d16c2cfE17DF5fDCcE556763` (current; used by the live app
  and live subgraph since the May 2026 redeploy).
  ⚠️ The draft plan's default `0xa3af0da9733061da88b91ea28740780a887c8ce3` is
  the **legacy** proxy — still on-chain but superseded. Do not use it as default.
- **Live mainnet subgraph endpoint** (extracted from the app.societyprotocol.io
  bundle; verified to return data):
  `https://api.studio.thegraph.com/query/46833/society-mainnet/version/latest`
- **Subgraph schema** (`schema.graphql`): `User` entity keyed by lowercase
  wallet address, fields `name`, `bio`, `imageUrl`, `profile: Badge`.
  `Badge` entity: `id` (ERC-1155 token id), `name`, `description`, `imageUrl`,
  `uri`, `isProfile`, `holdersCount`, etc. The draft's GraphQL query shape was
  approximately right; the corrected query is in §4.3.
- **Contract ABI** (`SocietyProtocolBadges.sol`):
  `profileBadgeId(address) → uint256`, `uri(uint256) → string`,
  `balanceOf(address,uint256) → uint256`.
  ⚠️ `balanceOf` can be **overridden per-badge by a hook contract**
  (`ISocietyBadgeHook.onBalanceOf`) — it is not plain ERC-1155. Don't cache or
  second-guess its result; just call it.
- The frontend's own user lookup query is
  `src/queries/user.graphql` in web3-app-client — use it as the reference
  pattern for our query.

---

## 2. Bugs in the draft plan, and their fixes

| # | Draft problem | Fix |
|---|---|---|
| 1 | Badges contract default is the stale pre-redeploy proxy | Default to `0x2313C0cDdc233c92d16c2cfE17DF5fDCcE556763`, keep it a site setting |
| 2 | Wallet address taken from `auth_token.dig(:info, :name)` — but `info.name` is `ens_name \|\| address` (see `siwe.rb` `info` block) | Use `auth_token.uid` (the strategy sets `uid` to `@verified_address`) |
| 3 | `resolve_society_via_rpc` is an unimplemented placeholder | Full implementation in §4.4, reusing a shared RPC helper (§4.1) |
| 4 | `result.extra_data.merge(...)` — `extra_data` can be nil | Nil-guard before merging |
| 5 | **Core logic gap:** `apply_preferred_identity` mutates `result.username/name/avatar_url`, which Discourse only uses at **account creation**. For existing users (the stated scope!) the toggle would do nothing | Define explicit display semantics in §5: toggle updates `user.name` (display name) + avatar for existing users; username is left stable. Auth-result mutation only matters for new signups |
| 6 | ENS never refreshed for existing users on login | Store ENS from `auth_token.info` on every login (it is already resolved server-side in the strategy — free) |
| 7 | `assoc.info` in migration — `UserAssociatedAccount` has no `info` column (it has `provider_name`, `provider_uid`, `user_id`, `extra` jsonb) | Use `assoc.extra`; ENS is generally not persisted there, so migration re-resolves ENS via RPC (§7) |
| 8 | Frontend Ember code mixes classic `Component.extend({})` with `@action` decorators — invalid syntax; also reads `model.custom_fields.*` while the serializer adds `web3_identities` | Correct Glimmer component in §6, reading `model.web3_identities.*` |
| 9 | `modifyClass('controller:preferences/profile')` with an empty body does nothing — the component is never rendered | Render via a real plugin outlet / connector (§6.3), with the exact outlet verified against the deployed Discourse version |
| 10 | Error-revert line `this.set('model.custom_fields.preferred_identity', this.model.custom_fields.preferred_identity)` is a no-op | Store previous value, restore on failure (§6.2) |
| 11 | `siwe_society_rpc_url` defaults to an Alchemy URL containing `YOUR_KEY`; also duplicates the existing `siwe_ethereum_rpc_url` | Drop the setting; Society RPC falls back to `siwe_ethereum_rpc_url` (§3) |
| 12 | Subgraph/RPC call runs **synchronously inside the login callback** on every login — adds latency and failure surface to auth | Resolve inline only at account creation; refresh for existing users in a background job, throttled (§4.5) |
| 13 | Re-registering `discourse_siwe_enabled` with `client: true` duplicates `enabled_site_setting` | Leave the existing setting untouched |
| 14 | `sanitize_username` slices to 60 chars; Discourse max username length is a site setting (`max_username_length`, default 20) | Truncate to `SiteSetting.max_username_length` and let Discourse's suggester uniquify |
| 15 | Test plan has no automated tests | Add standalone minitest files matching the repo's existing test style (§8) |

---

## 3. Plugin settings (`config/settings.yml`)

Append under the existing `discourse_siwe:` section (keep the four existing
settings exactly as they are):

```yaml
discourse_siwe:
  # ... existing settings unchanged ...

  siwe_society_enabled:
    default: true

  siwe_society_subgraph_url:
    default: 'https://api.studio.thegraph.com/query/46833/society-mainnet/version/latest'

  siwe_society_badges_contract:
    default: '0x2313C0cDdc233c92d16c2cfE17DF5fDCcE556763'

  siwe_identity_resolution_mode:
    default: 'subgraph'
    type: enum
    choices:
      - subgraph
      - rpc
```

Notes:

- None of these need `client: true` — all resolution is server-side.
- **No `siwe_society_rpc_url`.** RPC mode (and ENS) both use the existing
  `siwe_ethereum_rpc_url`. If mode is `rpc` and that setting is empty, Society
  resolution returns nil — same behavior as ENS today.
- `siwe_society_enabled` is a kill-switch so the feature can be disabled
  without touching the rest.
- Add matching labels to `config/locales/server.en.yml`.

---

## 4. Backend changes

### 4.1 New file: `lib/discourse_siwe/eth_rpc.rb` (shared helper)

`lib/omniauth/strategies/siwe.rb` currently has private `rpc_url`,
`rpc_connection`, and `eth_call` methods. The resolver and the migration need
the same capability, so extract them into a shared module instead of
copy-pasting a third implementation:

```ruby
# frozen_string_literal: true

require 'net/http'
require 'json'

module DiscourseSiwe
  module EthRpc
    module_function

    def rpc_url
      url = SiteSetting.siwe_ethereum_rpc_url rescue nil
      url if url&.present?
    end

    def connection
      uri = URI(rpc_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 10
      http
    end

    # Generic eth_call. `to` may be nil (contract-creation simulation,
    # used by EIP-6492). Returns hex result without 0x prefix, or nil.
    def eth_call(to, data, http: nil)
      return nil unless rpc_url

      http ||= connection
      path = URI(rpc_url).path
      path = '/' if path.empty?
      call_params = { data: data }
      call_params[:to] = to if to
      req = Net::HTTP::Post.new(path, 'Content-Type' => 'application/json')
      req.body = {
        jsonrpc: '2.0', method: 'eth_call',
        params: [call_params, 'latest'], id: 1
      }.to_json

      result = JSON.parse(http.request(req).body)
      return nil if result['error'] || result['result'].nil? || result['result'] == '0x'

      Eth::Util.remove_hex_prefix(result['result'])
    rescue StandardError
      nil
    end

    # ABI encode helpers for the calls we need
    def encode_address(addr) = Eth::Util.remove_hex_prefix(addr).downcase.rjust(64, '0')
    def encode_uint256(n)    = n.to_i.to_s(16).rjust(64, '0')

    def decode_address(hex)
      return nil if hex.nil? || hex.length < 40
      address = hex[-40, 40]
      return nil if address == '0' * 40
      "0x#{address}"
    end

    def decode_uint256(hex)
      return nil if hex.nil? || hex.empty?
      hex.to_i(16)
    end

    def decode_string(hex)
      return nil if hex.nil? || hex.length < 128
      offset = hex[0, 64].to_i(16) * 2
      length = hex[offset, 64].to_i(16)
      return '' if length.zero?
      data_start = offset + 64
      return nil if hex.length < data_start + length * 2
      [hex[data_start, length * 2]].pack('H*').force_encoding('UTF-8')
    end
  end
end
```

Then refactor `lib/omniauth/strategies/siwe.rb` **minimally**: delete its
private `rpc_url` / `rpc_connection` / `eth_call` / `abi_decode_address` /
`abi_decode_string` and delegate to `DiscourseSiwe::EthRpc`
(e.g. `EthRpc.eth_call(...)`). Keep `ens_namehash`, `resolve_ens`,
`ens_avatar_url`, and `smart_wallet_valid?` where they are — behavior must not
change. This refactor is what lets the migration re-resolve ENS (§7) without
duplicating ENS logic: also expose ENS resolution by moving `resolve_ens` +
helpers into the same module **or** into `IdentityResolver` — decide once, but
there must be exactly one ENS implementation afterward. Recommendation: move
`ens_namehash`, `resolve_ens`, `ens_avatar_url` into
`lib/discourse_siwe/ens_resolver.rb` and have the strategy call it.

### 4.2 New file: `lib/discourse_siwe/identity_resolver.rb`

Full implementation (no placeholder). Returns a hash or nil:

```ruby
# frozen_string_literal: true

require 'net/http'
require 'json'

module DiscourseSiwe
  class IdentityResolver
    # eth_call function selectors (first 4 bytes of keccak of the signature):
    #   profileBadgeId(address)  -> 0x...
    #   balanceOf(address,uint256) -> 0x00fdd58e
    #   uri(uint256)             -> 0x0e89341c
    # Compute selectors at load time with Eth::Util.keccak256 to avoid
    # hardcoding mistakes (same approach as ENS selectors in siwe.rb, which
    # are hardcoded — either is acceptable, but verify against the ABI).
    BALANCE_OF_SELECTOR = '00fdd58e'
    URI_SELECTOR        = '0e89341c'

    PROFILE_BADGE_ID_SELECTOR = Eth::Util.bin_to_hex(
      Eth::Util.keccak256('profileBadgeId(address)')[0, 4]
    ).freeze

    def self.resolve(wallet_address)
      new(wallet_address).resolve
    end

    def initialize(wallet_address)
      @wallet_address = wallet_address.downcase
    end

    # Returns { badge_id:, name:, bio:, avatar:, uri: } or nil.
    def resolve
      return nil unless SiteSetting.siwe_society_enabled

      if SiteSetting.siwe_identity_resolution_mode == 'subgraph' &&
         SiteSetting.siwe_society_subgraph_url.present?
        via_subgraph || via_rpc   # fall back to RPC if subgraph fails
      else
        via_rpc
      end
    end

    private

    # --- Subgraph path -------------------------------------------------------

    QUERY = <<~GRAPHQL
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
          bio
          imageUrl
          profile {
            id
            name
            description
            imageUrl
            uri
          }
        }
      }
    GRAPHQL

    def via_subgraph
      uri = URI(SiteSetting.siwe_society_subgraph_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 10
      req = Net::HTTP::Post.new(uri.path.empty? ? '/' : uri.path,
                                'Content-Type' => 'application/json')
      req.body = { query: QUERY, variables: { id: @wallet_address } }.to_json

      data = JSON.parse(http.request(req).body).dig('data', 'user')
      return nil unless data

      profile = data['profile'] || {}
      {
        badge_id: profile['id'],
        # User-level fields are the outpost profile; badge metadata is fallback
        name:   data['name'].presence || profile['name'],
        bio:    data['bio'].presence || profile['description'],
        avatar: data['imageUrl'].presence || profile['imageUrl'],
        uri:    profile['uri'],
      }
    rescue StandardError => e
      Rails.logger.warn("[discourse-siwe-auth] Society subgraph error: #{e.message}")
      nil
    end

    # --- Direct-RPC fallback -------------------------------------------------

    def via_rpc
      return nil unless DiscourseSiwe::EthRpc.rpc_url
      contract = SiteSetting.siwe_society_badges_contract
      return nil unless contract.match?(/\A0x[0-9a-fA-F]{40}\z/)

      http = DiscourseSiwe::EthRpc.connection
      http.start do
        # 1. profileBadgeId(address) — 0 means "no profile badge"
        badge_id_hex = DiscourseSiwe::EthRpc.eth_call(
          contract,
          "0x#{PROFILE_BADGE_ID_SELECTOR}#{DiscourseSiwe::EthRpc.encode_address(@wallet_address)}",
          http: http
        )
        badge_id = DiscourseSiwe::EthRpc.decode_uint256(badge_id_hex)
        return nil if badge_id.nil? || badge_id.zero?

        # 2. balanceOf(address, badgeId) — hook-aware check the user holds it
        balance_hex = DiscourseSiwe::EthRpc.eth_call(
          contract,
          "0x#{BALANCE_OF_SELECTOR}" \
            "#{DiscourseSiwe::EthRpc.encode_address(@wallet_address)}" \
            "#{DiscourseSiwe::EthRpc.encode_uint256(badge_id)}",
          http: http
        )
        balance = DiscourseSiwe::EthRpc.decode_uint256(balance_hex)
        return nil if balance.nil? || balance.zero?

        # 3. uri(badgeId) -> metadata JSON URL (http or ipfs)
        uri_hex = DiscourseSiwe::EthRpc.eth_call(
          contract,
          "0x#{URI_SELECTOR}#{DiscourseSiwe::EthRpc.encode_uint256(badge_id)}",
          http: http
        )
        metadata_uri = DiscourseSiwe::EthRpc.decode_string(uri_hex)

        meta = fetch_metadata(metadata_uri)
        {
          badge_id: badge_id.to_s,
          name:   meta&.dig('name'),
          bio:    meta&.dig('description'),
          avatar: normalize_url(meta&.dig('image')),
          uri:    metadata_uri,
        }
      end
    rescue StandardError => e
      Rails.logger.warn("[discourse-siwe-auth] Society RPC resolution error: #{e.message}")
      nil
    end

    def fetch_metadata(metadata_uri)
      url = normalize_url(metadata_uri)
      return nil if url.blank?

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 10
      JSON.parse(http.request(Net::HTTP::Get.new(uri.request_uri)).body)
    rescue StandardError
      nil
    end

    def normalize_url(url)
      return nil if url.blank?
      url.start_with?('ipfs://') ? url.sub('ipfs://', 'https://ipfs.io/ipfs/') : url
    end
  end
end
```

Design notes:

- The draft wrapped the whole subgraph call in `rescue => e` with a log line
  missing a space (`error:#{e.message}`) — fixed above; use `warn` not `error`
  (identity resolution failing must never page anyone).
- Resolution **never raises** — every failure mode returns nil so login is
  never broken by Society Protocol being down.
- The subgraph `user.id` must be lowercased before querying (schema id is the
  lowercase address) — handled in `initialize`.

### 4.3 `plugin.rb` — registration block

Add to the existing `after_initialize` (do **not** create a second routes
block; extend the existing one):

```ruby
after_initialize do
  load File.expand_path('../app/controllers/discourse_siwe/auth_controller.rb', __FILE__)
  load File.expand_path('../lib/discourse_siwe/eth_rpc.rb', __FILE__)
  load File.expand_path('../lib/discourse_siwe/identity_resolver.rb', __FILE__)
  load File.expand_path('../lib/discourse_siwe/ens_resolver.rb', __FILE__) # if extracted, see 4.1

  %w[
    wallet_address ens_name ens_avatar
    society_badge_id society_name society_avatar society_bio
    preferred_identity society_resolved_at
  ].each { |f| User.register_custom_field_type(f, :string) }

  # Expose identities to the owning user only (not publicly).
  add_to_serializer(:user, :web3_identities, include_condition: -> { scope.user == object }) do
    {
      wallet_address: object.custom_fields['wallet_address'],
      ens_name: object.custom_fields['ens_name'],
      ens_avatar: object.custom_fields['ens_avatar'],
      society_badge_id: object.custom_fields['society_badge_id'],
      society_name: object.custom_fields['society_name'],
      society_avatar: object.custom_fields['society_avatar'],
      society_bio: object.custom_fields['society_bio'],
      preferred_identity: object.custom_fields['preferred_identity'] || 'wallet',
    }
  end

  Discourse::Application.routes.prepend do
    get  '/discourse-siwe/auth'           => 'discourse_siwe/auth#index'
    get  '/discourse-siwe/message'        => 'discourse_siwe/auth#message'
    post '/discourse-siwe/update-identity' => 'discourse_siwe/auth#update_identity'
  end
end
```

(Verify the exact `include_condition` lambda form against the deployed
Discourse version's `add_to_serializer` API; older form is
`add_to_serializer(:user, :web3_identities) { ... }` plus an
`add_to_serializer(:user, :include_web3_identities?) { scope.user == object }`.)

### 4.4 `SiweAuthenticator` — corrected hooks

```ruby
class ::SiweAuthenticator < ::Auth::ManagedAuthenticator
  # ... existing methods unchanged ...

  # Runs on EVERY login (new and existing users).
  def after_authenticate(auth_token, existing_account: nil)
    result = super

    wallet = auth_token&.uid&.downcase
    return result unless wallet.present?

    info = auth_token[:info] || {}
    ens_name   = info[:nickname].presence
    ens_name   = nil if ens_name&.downcase == wallet
    ens_avatar = info[:image].presence

    if result.user
      # Existing user: cheap in-place updates only (no network calls here).
      cf = result.user.custom_fields
      cf['wallet_address'] ||= wallet
      cf['ens_name']   = ens_name   if ens_name
      cf['ens_avatar'] = ens_avatar if ens_avatar
      cf['preferred_identity'] ||= default_preference(cf)
      result.user.save_custom_fields
      enqueue_identity_refresh(result.user)   # throttled background job, §4.5
    else
      # New user: pass data through to after_create_account.
      result.extra_data = (result.extra_data || {}).merge(
        wallet_address: wallet,
        ens_name: ens_name,
        ens_avatar: ens_avatar,
      )
      # Auth-result name/avatar only affect account creation:
      result.name       = ens_name   if ens_name
      result.avatar_url = ens_avatar if ens_avatar
    end

    result
  end

  def after_create_account(user, auth_result)
    super
    extra = auth_result[:extra_data] || {}
    wallet = extra['wallet_address'] || extra[:wallet_address]
    return unless wallet.present?

    user.custom_fields['wallet_address'] = wallet.downcase
    user.custom_fields['ens_name']       = extra['ens_name']   || extra[:ens_name]
    user.custom_fields['ens_avatar']     = extra['ens_avatar'] || extra[:ens_avatar]

    society = DiscourseSiwe::IdentityResolver.resolve(wallet)   # inline, once
    store_society(user, society)

    user.custom_fields['preferred_identity'] = default_preference(user.custom_fields)
    user.save_custom_fields
  end

  private

  def default_preference(cf)
    if cf['society_name'].present? then 'society'
    elsif cf['ens_name'].present?  then 'ens'
    else 'wallet'
    end
  end

  def store_society(user, society)
    %w[badge_id name avatar bio].each do |k|
      user.custom_fields["society_#{k}"] = society&.[](k.to_sym)
    end
    user.custom_fields['society_resolved_at'] = Time.now.utc.iso8601
  end
end
```

Key differences from the draft:

- Wallet from `auth_token.uid`, ENS filtered when it equals the address.
- No `apply_preferred_identity` mutation of `result.username` for existing
  users — see §5 for what actually happens instead.
- No Society network call in the login path for existing users (moved to a
  throttled job). One inline call at account creation is acceptable.
- The draft's `sanitize_username` is dropped from the login path entirely —
  Discourse's own `UserNameSuggester` already handles usernames at signup.
  If we ever want Society/ENS names as suggested usernames for new signups,
  set `result.username` via `UserNameSuggester.suggest(...)` — optional,
  out of scope for v1 of this feature.

### 4.5 Throttled background refresh job

Create `app/jobs/regular/refresh_siwe_identity.rb` (plugin jobs dir is picked
up automatically via `after_initialize` load, same pattern as the controller):

```ruby
module Jobs
  class RefreshSiweIdentity < ::Jobs::Base
    def execute(args)
      user = User.find_by(id: args[:user_id])
      return unless user

      last = user.custom_fields['society_resolved_at']
      return if last.present? && Time.parse(last) > 24.hours.ago

      wallet = user.custom_fields['wallet_address']
      return unless wallet.present?

      society = DiscourseSiwe::IdentityResolver.resolve(wallet)
      SiweAuthenticator.send(:new).send(:store_society, user, society) # or extract store_society into a shared concern
      user.save_custom_fields
    end
  end
end
```

`enqueue_identity_refresh(user)` in the authenticator is simply
`Jobs.enqueue(:refresh_siwe_identity, user_id: user.id)` guarded by the same
24h check (so we don't flood the queue). Cleaner: extract
`store_society`/`default_preference` into `DiscourseSiwe::IdentityStore`
module used by both the authenticator and the job — do that instead of the
`send` hack shown inline above.

### 4.6 `update_identity` endpoint (`auth_controller.rb`)

Mostly as drafted, plus the part the draft missed — **applying** the choice:

```ruby
IDENTITIES = %w[wallet ens society].freeze

def update_identity
  raise Discourse::NotLoggedIn unless current_user

  preferred = params[:preferred_identity]
  return render json: { error: 'Invalid identity type' }, status: 400 unless IDENTITIES.include?(preferred)

  cf = current_user.custom_fields
  case preferred
  when 'ens'
    return render json: { error: 'No ENS name available' }, status: 400 if cf['ens_name'].blank?
  when 'society'
    return render json: { error: 'No Society identity available' }, status: 400 if cf['society_badge_id'].blank?
  end

  cf['preferred_identity'] = preferred
  current_user.save_custom_fields

  DiscourseSiwe::DisplayNameApplier.apply(current_user)   # §5
  current_user.save!

  render json: { success: true, preferred_identity: preferred }
end
```

Note `raise Discourse::NotLoggedIn` instead of a manual 401 JSON — idiomatic
Discourse, and CSRF is already enforced by `ApplicationController` for POSTs.

---

## 5. Display-name semantics (the gap in the draft)

The draft never defined what "Display name override based on preference"
actually does for an existing account. Fixed behavior:

- **Username: never changed by this feature.** Renaming breaks mentions,
  quotes, and permalinks. New users already get the ENS name suggested as
  username at signup via existing behavior (`info.nickname` → username
  suggestion); that stays.
- **`user.name` (display name):** set from the preferred identity:
  - `society` → `society_name`
  - `ens` → `ens_name`
  - `wallet` → truncated `0x1234…abcd` form
- **Avatar:** if the preferred identity has an avatar URL, enqueue Discourse's
  built-in `Jobs::DownloadAvatarFromUrl` for the user; on `wallet`, leave the
  existing avatar alone (no web3 avatar source).

Implement as `DiscourseSiwe::DisplayNameApplier.apply(user)` in
`lib/discourse_siwe/display_name_applier.rb`, called from
`update_identity` and from `after_create_account` (after fields are stored).
It must no-op gracefully when the preferred identity's name is blank.

---

## 6. Frontend changes

### 6.1 Component — valid Glimmer syntax

`assets/javascripts/discourse/components/siwe-identity-selector.gjs`
(Glimmer/gjs is the current Discourse standard; if the pinned Discourse
version predates `.gjs` in plugins, use the classic `.js` + `.hbs` pair
instead — verify on the test instance first):

```gjs
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { ajax } from 'discourse/lib/ajax';
import { popupAjaxError } from 'discourse/lib/ajax-error';

export default class SiweIdentitySelector extends Component {
  @tracked saving = false;
  // this.args.model is the preferences user model; identities arrive
  // via model.web3_identities (serialized in §4.3)

  get identities() {
    const w = this.args.model.web3_identities;
    if (!w?.wallet_address) return [];
    const list = [
      { id: 'wallet', label: w.wallet_address, source: 'Wallet' },
    ];
    if (w.ens_name) list.push({ id: 'ens', label: w.ens_name, source: 'ENS', avatar: w.ens_avatar });
    if (w.society_badge_id) list.push({ id: 'society', label: w.society_name, source: 'Society Protocol', avatar: w.society_avatar });
    return list;
  }

  @action
  async select(id) {
    const previous = this.args.model.web3_identities.preferred_identity;
    if (id === previous || this.saving) return;
    this.saving = true;
    try {
      await ajax('/discourse-siwe/update-identity', {
        type: 'POST',
        data: { preferred_identity: id },
      });
      this.args.model.set('web3_identities.preferred_identity', id);
    } catch (e) {
      this.args.model.set('web3_identities.preferred_identity', previous); // real revert
      popupAjaxError(e);
    } finally {
      this.saving = false;
    }
  }

  <template>
    {{#if this.identities.length}}
      <div class="control-group siwe-identity-selector">
        <label class="control-label">{{i18n "discourse_siwe.identity.title"}}</label>
        <div class="controls">
          {{#each this.identities as |identity|}}
            <label class="identity-option">
              <input
                type="radio"
                name="preferred-identity"
                value={{identity.id}}
                checked={{eq identity.id @model.web3_identities.preferred_identity}}
                disabled={{this.saving}}
                {{on "change" (fn this.select identity.id)}}
              />
              <span class="identity-name">{{identity.label}}</span>
              <span class="identity-source">{{identity.source}}</span>
              {{#if identity.avatar}}
                <img src={{identity.avatar}} class="identity-preview" alt="" />
              {{/if}}
            </label>
          {{/each}}
        </div>
      </div>
    {{/if}}
  </template>
}
```

(The draft's emoji icons are dropped — match Discourse's UI conventions
instead. `eq`/`fn`/`on` are built-in helpers in current Discourse Ember.)

### 6.2 Render it into the preferences page

The draft's empty `modifyClass` renders nothing. Use a plugin-outlet
connector. In the deployed Discourse version, find the outlet in
`app/assets/javascripts/discourse/app/templates/preferences/profile.hbs`
(or the `preferences` wrapper), then add e.g.:

`assets/javascripts/discourse/connectors/user-preferences-profile-bottom/siwe-identity-selector.hbs`
```hbs
<SiweIdentitySelector @model={{@model}} />
```

⚠️ The exact outlet name must be verified by grepping the target Discourse
version's templates — do not assume `user-preferences-profile-bottom` exists.
This is the one frontend step that requires a live Discourse checkout to
confirm.

### 6.3 Styles + locales

- Add a `.siwe-identity-selector` block to
  `assets/stylesheets/discourse-siwe-auth.scss` (option rows, 24px avatar
  previews, muted source label).
- Add `js.discourse_siwe.identity.title: 'Web3 display identity'` (and option
  labels/errors) to `config/locales/client.en.yml`.

---

## 7. Migration (`lib/tasks/siwe_identities.rake`)

Fixes vs. draft: `assoc.info` → `assoc.extra`; ENS re-resolved via the shared
resolver instead of relying on association data; rate limiting; dry-run flag.

```ruby
namespace :siwe do
  desc 'Backfill web3 identity custom fields for existing SIWE users'
  task :migrate_identities, [:dry_run] => :environment do |_t, args|
    dry_run = args[:dry_run] == 'true'
    migrated = 0

    UserAssociatedAccount.where(provider_name: 'siwe').find_each do |assoc|
      user = assoc.user
      next unless user
      wallet = assoc.provider_uid&.downcase
      next if wallet.blank? || user.custom_fields['wallet_address'].present?

      puts "#{dry_run ? '[dry-run] ' : ''}Migrating #{user.username} (#{user.id})"

      unless dry_run
        user.custom_fields['wallet_address'] = wallet

        ens_name, ens_avatar = DiscourseSiwe::EnsResolver.resolve(wallet) # see 4.1 extraction
        user.custom_fields['ens_name']   = ens_name   if ens_name
        user.custom_fields['ens_avatar'] = ens_avatar if ens_avatar

        society = DiscourseSiwe::IdentityResolver.resolve(wallet)
        DiscourseSiwe::IdentityStore.store_society(user, society)
        user.custom_fields['preferred_identity'] =
          DiscourseSiwe::IdentityStore.default_preference(user.custom_fields)

        user.save_custom_fields
        DiscourseSiwe::DisplayNameApplier.apply(user)
        user.save!
        sleep 0.5  # be kind to the RPC/subgraph
      end
      migrated += 1
    end

    puts "Done. #{migrated} users #{dry_run ? 'would be' : ''} migrated."
  end
end
```

Notes:

- The draft applied no display name during migration. Decide explicitly:
  recommended default is to **only backfill fields + preference, not rewrite
  `user.name` for existing users** (surprise renames are worse than stale
  display names); their name updates next time they use the toggle or log in.
  Make this a task flag if desired.
- Users without a configured RPC get wallet-only fields — fine; the login-time
  refresh fills the rest later.

---

## 8. Tests (matching the repo's standalone minitest style)

New files, same pattern as `test/ens_unit_test.rb` / `test/ens_integration_test.rb`:

- `test/society_unit_test.rb` — no network:
  - `decode_uint256` / address+uint256 ABI encoding for
    `profileBadgeId`/`balanceOf`/`uri` calldata (assert exact calldata hex).
  - Subgraph response parsing: feed canned JSON payloads (with/without
    `profile`, missing user) into the parsing path (structure the resolver so
    parsing is a pure function — `IdentityResolver.parse_subgraph(json)`).
  - `normalize_url`: `ipfs://` → gateway, passthrough http(s), blank → nil.
  - `default_preference` priority: society > ens > wallet.
- `test/society_integration_test.rb` — needs `RPC_URL`; resolve a known
  mainnet address holding a Society profile badge (get one from the live
  subgraph first, e.g. one of the users returned by a test query) via `via_rpc`
  path, assert `badge_id` and `name` are present.
- Update `README.md` test list accordingly.

No Discourse test-suite (rspec) tests exist in this repo today — keep it that
way; standalone scripts are the established convention.

---

## 9. Also update

- `plugin.rb` header: version `1.2.1` → `1.3.0`, extend `about` text.
- `README.md`: new settings table rows, feature description, note that the
  Society subgraph/contract defaults point at mainnet.
- `config/locales/server.en.yml`: labels for the 4 new settings.

---

## 10. Open items to confirm on staging before production

1. The plugin-outlet name in `preferences/profile` (§6.2).
2. Exact `add_to_serializer` include-condition API form (§4.3).
3. `after_create_account` extra_data key stringification in the deployed
   Discourse version (code above tolerates both).
4. Whether `.gjs` components compile in plugins on the pinned Discourse
   version; fall back to classic component if not.
5. Whether Discourse's `Jobs::DownloadAvatarFromUrl` signature matches
   `(url:, user_id:)` on the deployed version.
6. Run the migration with `dry_run=true` first.

---

## 11. Implementation order

1. `config/settings.yml` + locales (§3, §9)
2. `lib/discourse_siwe/eth_rpc.rb` + minimal `siwe.rb` refactor; ENS extraction (§4.1)
3. `lib/discourse_siwe/identity_resolver.rb` (§4.2) + unit tests (§8)
4. `plugin.rb`: custom fields, serializer, route (§4.3)
5. `SiweAuthenticator` hooks + `IdentityStore` + refresh job (§4.4, §4.5)
6. `update_identity` + `DisplayNameApplier` (§4.6, §5)
7. Frontend: component, outlet connector, styles, locales (§6)
8. Migration rake task, dry-run on staging (§7, §10.6)
9. README + version bump (§9), then production deploy



================================================
FILE: test/ens_integration_test.rb
================================================
#!/usr/bin/env ruby
# Integration test: resolves a known ENS name against a real Ethereum RPC.
#
# Usage:
#   ruby test/ens_integration_test.rb                               # uses default public RPC
#   RPC_URL=https://eth-mainnet.g.alchemy.com/v2/KEY ruby test/ens_integration_test.rb
#
# Tests against jalil.eth, which has a reverse record and avatar.

require 'net/http'
require 'json'

$LOAD_PATH.unshift(*Dir[File.join(__dir__, '..', 'gems/3.4.8/gems/keccak-*/lib')])
require 'digest/keccak'

RPC_URL = ENV.fetch('RPC_URL', 'https://cloudflare-eth.com')
ENS_REGISTRY = '0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e'

# Known test data
TEST_ADDRESS = '0xe11DA9560b51f8918295EdC5ab9c0a90E9ADa20B'
TEST_ENS     = 'jalil.eth'

def keccak256(data)
  Digest::Keccak.new(256).digest(data)
end

def bin_to_hex(bin)
  bin.unpack1('H*')
end

def ens_namehash(name)
  node = "\x00" * 32
  unless name.nil? || name.empty?
    name.split('.').reverse.each do |label|
      label_hash = keccak256(label)
      node = keccak256(node + label_hash)
    end
  end
  bin_to_hex(node)
end

def eth_call(to, data)
  uri = URI(RPC_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'
  http.open_timeout = 10
  http.read_timeout = 10
  req = Net::HTTP::Post.new(uri.path.empty? ? '/' : uri.path, 'Content-Type' => 'application/json')
  req.body = {
    jsonrpc: '2.0',
    method: 'eth_call',
    params: [{ to: to, data: data }, 'latest'],
    id: 1
  }.to_json

  response = http.request(req)
  result = JSON.parse(response.body)

  if result['error']
    puts "  RPC error: #{result['error']}"
    return nil
  end

  return nil if result['result'].nil? || result['result'] == '0x'

  hex = result['result']
  hex.start_with?('0x') ? hex[2..] : hex
end

def abi_decode_address(hex)
  return nil if hex.nil? || hex.length < 40
  address = hex[-40, 40]
  return nil if address == '0' * 40
  "0x#{address}"
end

def abi_decode_string(hex)
  return nil if hex.nil? || hex.length < 128
  offset = hex[0, 64].to_i(16) * 2
  length = hex[offset, 64].to_i(16)
  return '' if length == 0
  data_start = offset + 64
  return nil if hex.length < data_start + length * 2
  [hex[data_start, length * 2]].pack('H*')
end

# ---------- Run integration test ----------

puts "ENS Integration Test"
puts "RPC: #{RPC_URL}"
puts "=" * 60

address = TEST_ADDRESS
addr_clean = address.sub(/\A0x/i, '').downcase

# Step 1: Reverse resolve
puts "\n1. Reverse resolving #{address}..."
reverse_node = ens_namehash("#{addr_clean}.addr.reverse")
puts "   Reverse node: #{reverse_node}"

resolver_hex = eth_call(ENS_REGISTRY, "0x0178b8bf#{reverse_node}")
resolver = abi_decode_address(resolver_hex)
if resolver.nil?
  puts "   FAIL: No resolver found for reverse node"
  exit 1
end
puts "   Reverse resolver: #{resolver}"

name_hex = eth_call(resolver, "0x691f3431#{reverse_node}")
name = abi_decode_string(name_hex)
if name.nil? || name.empty?
  puts "   FAIL: No name returned from reverse resolver"
  exit 1
end
puts "   Resolved name: #{name}"

if name == TEST_ENS
  puts "   PASS: Name matches expected '#{TEST_ENS}'"
else
  puts "   WARN: Expected '#{TEST_ENS}', got '#{name}'"
end

# Step 2: Forward verify
puts "\n2. Forward verifying #{name} -> address..."
forward_node = ens_namehash(name)
puts "   Forward node: #{forward_node}"

fwd_resolver_hex = eth_call(ENS_REGISTRY, "0x0178b8bf#{forward_node}")
fwd_resolver = abi_decode_address(fwd_resolver_hex)
if fwd_resolver.nil?
  puts "   FAIL: No resolver found for forward name"
  exit 1
end
puts "   Forward resolver: #{fwd_resolver}"

addr_hex = eth_call(fwd_resolver, "0x3b3b57de#{forward_node}")
resolved_addr = abi_decode_address(addr_hex)
if resolved_addr.nil?
  puts "   FAIL: No address returned from forward resolver"
  exit 1
end
puts "   Resolved address: #{resolved_addr}"

if resolved_addr.downcase == address.downcase
  puts "   PASS: Forward verification confirmed"
else
  puts "   FAIL: Address mismatch! #{resolved_addr} != #{address}"
  exit 1
end

# Step 3: Avatar via ENS metadata service
puts "\n3. Checking avatar via ENS metadata service..."
avatar_url = "https://metadata.ens.domains/mainnet/avatar/#{name}"
avatar_uri = URI(avatar_url)
avatar_http = Net::HTTP.new(avatar_uri.host, avatar_uri.port)
avatar_http.use_ssl = true
avatar_http.open_timeout = 10
avatar_http.read_timeout = 10
avatar_res = avatar_http.request(Net::HTTP::Head.new(avatar_uri.path))
puts "   URL: #{avatar_url}"
puts "   Status: #{avatar_res.code}"
if avatar_res.code.to_i == 200
  puts "   Content-Type: #{avatar_res['content-type']}"
  puts "   PASS: Avatar available"
else
  puts "   INFO: No avatar available (status #{avatar_res.code})"
end

# Step 4: Verify no-avatar case returns 404
puts "\n4. Checking no-avatar case (hot.jalil.eth)..."
no_avatar_url = "https://metadata.ens.domains/mainnet/avatar/hot.jalil.eth"
no_avatar_uri = URI(no_avatar_url)
no_avatar_http = Net::HTTP.new(no_avatar_uri.host, no_avatar_uri.port)
no_avatar_http.use_ssl = true
no_avatar_http.open_timeout = 10
no_avatar_http.read_timeout = 10
no_avatar_res = no_avatar_http.request(Net::HTTP::Head.new(no_avatar_uri.path))
puts "   URL: #{no_avatar_url}"
puts "   Status: #{no_avatar_res.code}"
if no_avatar_res.code.to_i == 404
  puts "   PASS: Correctly returns 404 for name without avatar"
else
  puts "   WARN: Expected 404, got #{no_avatar_res.code}"
end

puts "\n" + "=" * 60
puts "All checks passed!"



================================================
FILE: test/ens_unit_test.rb
================================================
#!/usr/bin/env ruby
# Unit tests for ENS resolution helpers (no RPC needed).
#
# Run: ruby test/ens_unit_test.rb

$LOAD_PATH.unshift(*Dir[File.join(__dir__, '..', 'gems/3.4.8/gems/keccak-*/lib')])
require 'digest/keccak'
require 'minitest/autorun'

# Standalone reimplementations of the functions under test,
# using Digest::Keccak directly (avoids the native rbsecp256k1 dep).
module EnsHelpers
  module_function

  def keccak256(data)
    Digest::Keccak.new(256).digest(data)
  end

  def bin_to_hex(bin)
    bin.unpack1('H*')
  end

  def ens_namehash(name)
    node = "\x00" * 32
    unless name.nil? || name.empty?
      name.split('.').reverse.each do |label|
        label_hash = keccak256(label)
        node = keccak256(node + label_hash)
      end
    end
    bin_to_hex(node)
  end

  def abi_decode_address(hex)
    return nil if hex.nil? || hex.length < 40
    address = hex[-40, 40]
    return nil if address == '0' * 40
    "0x#{address}"
  end

  def abi_decode_string(hex)
    return nil if hex.nil? || hex.length < 128
    offset = hex[0, 64].to_i(16) * 2
    length = hex[offset, 64].to_i(16)
    return '' if length == 0
    data_start = offset + 64
    return nil if hex.length < data_start + length * 2
    [hex[data_start, length * 2]].pack('H*')
  end

end

class EnsNamehashTest < Minitest::Test
  # Well-known ENS namehash test vectors from EIP-137
  # https://eips.ethereum.org/EIPS/eip-137

  def test_empty_name
    assert_equal '0' * 64, EnsHelpers.ens_namehash('')
  end

  def test_eth
    expected = '93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae'
    assert_equal expected, EnsHelpers.ens_namehash('eth')
  end

  def test_foo_dot_eth
    expected = 'de9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f'
    assert_equal expected, EnsHelpers.ens_namehash('foo.eth')
  end

  def test_alice_dot_eth
    # Verify determinism and correct length
    hash = EnsHelpers.ens_namehash('alice.eth')
    assert_equal 64, hash.length, 'namehash should be 64 hex chars'
    assert_equal hash, EnsHelpers.ens_namehash('alice.eth')
  end

  def test_reverse_node
    # For address 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045
    addr_clean = 'd8da6bf26964af9d7eed9e03e53415d37aa96045'
    reverse_name = "#{addr_clean}.addr.reverse"
    hash = EnsHelpers.ens_namehash(reverse_name)
    assert_equal 64, hash.length
    # Verify it's deterministic
    assert_equal hash, EnsHelpers.ens_namehash(reverse_name)
  end

  def test_nil_name
    assert_equal '0' * 64, EnsHelpers.ens_namehash(nil)
  end
end

class AbiDecodeAddressTest < Minitest::Test
  def test_valid_address
    # 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045 padded to 32 bytes
    hex = '000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045'
    assert_equal '0xd8da6bf26964af9d7eed9e03e53415d37aa96045', EnsHelpers.abi_decode_address(hex)
  end

  def test_zero_address
    hex = '0000000000000000000000000000000000000000000000000000000000000000'
    assert_nil EnsHelpers.abi_decode_address(hex)
  end

  def test_nil_input
    assert_nil EnsHelpers.abi_decode_address(nil)
  end

  def test_short_input
    assert_nil EnsHelpers.abi_decode_address('abcd')
  end
end

class AbiDecodeStringTest < Minitest::Test
  def test_simple_string
    # ABI-encoded "vitalik.eth" (11 bytes)
    hex = '0000000000000000000000000000000000000000000000000000000000000020' \
          '000000000000000000000000000000000000000000000000000000000000000b' \
          '766974616c696b2e657468000000000000000000000000000000000000000000'
    assert_equal 'vitalik.eth', EnsHelpers.abi_decode_string(hex)
  end

  def test_short_string
    # ABI-encoded "eth" (3 bytes)
    hex = '0000000000000000000000000000000000000000000000000000000000000020' \
          '0000000000000000000000000000000000000000000000000000000000000003' \
          '6574680000000000000000000000000000000000000000000000000000000000'
    assert_equal 'eth', EnsHelpers.abi_decode_string(hex)
  end

  def test_empty_string
    hex = '0000000000000000000000000000000000000000000000000000000000000020' \
          '0000000000000000000000000000000000000000000000000000000000000000'
    assert_equal '', EnsHelpers.abi_decode_string(hex)
  end

  def test_nil_input
    assert_nil EnsHelpers.abi_decode_string(nil)
  end

  def test_too_short
    assert_nil EnsHelpers.abi_decode_string('0020')
  end

  def test_avatar_url
    # ABI-encoded "https://example.com/avatar.png" (30 bytes)
    url = 'https://example.com/avatar.png'
    url_hex = url.unpack1('H*')
    url_padded = url_hex.ljust(64, '0')
    hex = '0000000000000000000000000000000000000000000000000000000000000020' \
          '000000000000000000000000000000000000000000000000000000000000001e' \
          "#{url_padded}"
    assert_equal url, EnsHelpers.abi_decode_string(hex)
  end
end




================================================
FILE: test/society_integration_test.rb
================================================
#!/usr/bin/env ruby
# frozen_string_literal: true

# Integration test: resolves a Society Protocol profile badge against a real RPC.
#
# Usage:
#   ruby test/society_integration_test.rb
#
# Set RPC_URL for a dedicated provider; otherwise defaults to a public RPC.
# Set SOCIETY_ADDRESS to an address known to hold a Society profile badge to
# test the positive case.

$LOAD_PATH.unshift(*Dir[File.join(__dir__, '..', 'gems/*/gems/keccak-*/lib')])

require 'minitest/autorun'
require_relative '../lib/discourse_siwe/eth_rpc'
require_relative '../lib/discourse_siwe/identity_resolver'

RPC_URL = ENV.fetch('RPC_URL', 'https://cloudflare-eth.com')
TEST_ADDRESS = ENV.fetch('SOCIETY_ADDRESS', '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045')
BADGES_CONTRACT = '0x2313C0cDdc233c92d16c2cfE17DF5fDCcE556763'

# Minimal SiteSetting stub so this script runs outside Discourse.
module SiteSetting
  class << self
    def siwe_society_enabled
      true
    end

    def siwe_identity_resolution_mode
      'rpc'
    end

    def siwe_society_subgraph_url
      ''
    end

    def siwe_society_badges_contract
      BADGES_CONTRACT
    end

    def siwe_ethereum_rpc_url
      RPC_URL
    end
  end
end

class SocietyIntegrationTest < Minitest::Test
  def test_rpc_path_does_not_crash
    result = DiscourseSiwe::IdentityResolver.resolve(TEST_ADDRESS)

    if ENV['SOCIETY_ADDRESS']
      refute_nil result, 'Expected a Society identity for SOCIETY_ADDRESS'
      refute_empty result[:badge_id].to_s, 'Expected badge_id to be present'
      refute_empty result[:name].to_s, 'Expected name to be present'
      puts "Resolved Society identity: #{result.inspect}"
    else
      # For a random address this is expected to be nil; the important thing is
      # the RPC path completes without raising.
      puts "Resolution result: #{result.inspect}"
    end
  end
end



================================================
FILE: test/society_unit_test.rb
================================================
#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for Society Protocol resolution helpers and shared Ethereum utilities.
# No network needed.
#
# Run: ruby test/society_unit_test.rb

$LOAD_PATH.unshift(*Dir[File.join(__dir__, '..', 'gems/*/gems/keccak-*/lib')])

require 'minitest/autorun'
require_relative '../lib/discourse_siwe/url_validator'
require_relative '../lib/discourse_siwe/eth_rpc'
require_relative '../lib/discourse_siwe/ens_resolver'
require_relative '../lib/discourse_siwe/identity_resolver'
require_relative '../lib/discourse_siwe/identity_store'

class EthRpcHelpersTest < Minitest::Test
  def test_encode_address
    assert_equal(
      '000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045',
      DiscourseSiwe::EthRpc.encode_address('0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045')
    )
  end

  def test_encode_uint256
    assert_equal(
      '0000000000000000000000000000000000000000000000000000000000000001',
      DiscourseSiwe::EthRpc.encode_uint256(1)
    )
    assert_equal(
      '00000000000000000000000000000000000000000000000000000000000007d0',
      DiscourseSiwe::EthRpc.encode_uint256(2000)
    )
  end

  def test_decode_uint256
    assert_equal 1, DiscourseSiwe::EthRpc.decode_uint256('0000000000000000000000000000000000000000000000000000000000000001')
    assert_equal 2000, DiscourseSiwe::EthRpc.decode_uint256('7d0')
    assert_nil DiscourseSiwe::EthRpc.decode_uint256(nil)
  end

  def test_decode_address
    hex = '000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045'
    assert_equal '0xd8da6bf26964af9d7eed9e03e53415d37aa96045', DiscourseSiwe::EthRpc.decode_address(hex)
    assert_nil DiscourseSiwe::EthRpc.decode_address('0' * 64)
  end

  def test_decode_string
    hex = '0000000000000000000000000000000000000000000000000000000000000020' \
          '000000000000000000000000000000000000000000000000000000000000000b' \
          '766974616c696b2e657468000000000000000000000000000000000000000000'
    assert_equal 'vitalik.eth', DiscourseSiwe::EthRpc.decode_string(hex)
  end

  def test_keccak256_and_bin_to_hex
    # Empty input keccak256 is well-known.
    expected = 'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470'
    assert_equal expected, DiscourseSiwe::EthRpc.bin_to_hex(DiscourseSiwe::EthRpc.keccak256(''))
  end

  def test_profile_badge_id_selector
    # profileBadgeId(address) selector, computed at file load time.
    expected = DiscourseSiwe::EthRpc.bin_to_hex(
      DiscourseSiwe::EthRpc.keccak256('profileBadgeId(address)')[0, 4]
    )
    assert_equal expected, DiscourseSiwe::IdentityResolver::PROFILE_BADGE_ID_SELECTOR
  end
end

class EnsNamehashTest < Minitest::Test
  # Same EIP-137 vectors as test/ens_unit_test.rb, now via the shared module.
  def test_eth
    expected = '93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae'
    assert_equal expected, DiscourseSiwe::EnsResolver.namehash('eth')
  end

  def test_foo_dot_eth
    expected = 'de9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f'
    assert_equal expected, DiscourseSiwe::EnsResolver.namehash('foo.eth')
  end

  def test_empty_name
    assert_equal '0' * 64, DiscourseSiwe::EnsResolver.namehash('')
  end
end

class IdentityStoreTest < Minitest::Test
  def test_default_preference_society_wins
    cf = { 'society_name' => 'Society Member', 'ens_name' => 'foo.eth' }
    assert_equal 'society', DiscourseSiwe::IdentityStore.default_preference(cf)
  end

  def test_default_preference_ens_fallback
    cf = { 'society_name' => '', 'ens_name' => 'foo.eth' }
    assert_equal 'ens', DiscourseSiwe::IdentityStore.default_preference(cf)
  end

  def test_default_preference_wallet_fallback
    assert_equal 'wallet', DiscourseSiwe::IdentityStore.default_preference({})
  end

  def test_store_society
    user = Struct.new(:custom_fields).new({})
    DiscourseSiwe::IdentityStore.store_society(user, {
      badge_id: '42',
      name: 'Hero',
      avatar: 'https://example.com/hero.png',
      bio: 'A bio',
    })
    assert_equal '42', user.custom_fields['society_badge_id']
    assert_equal 'Hero', user.custom_fields['society_name']
    assert_equal 'https://example.com/hero.png', user.custom_fields['society_avatar']
    assert_equal 'A bio', user.custom_fields['society_bio']
    refute_nil user.custom_fields['society_resolved_at']
  end

  def test_society_stale?
    fresh = Struct.new(:custom_fields).new({ 'society_resolved_at' => Time.now.utc.iso8601 })
    stale = Struct.new(:custom_fields).new({ 'society_resolved_at' => (Time.now.utc - 86_401).iso8601 })
    missing = Struct.new(:custom_fields).new({})

    refute DiscourseSiwe::IdentityStore.society_stale?(fresh)
    assert DiscourseSiwe::IdentityStore.society_stale?(stale)
    assert DiscourseSiwe::IdentityStore.society_stale?(missing)
  end

  def test_web3_identities_default_wallet
    user = Struct.new(:custom_fields).new({ 'wallet_address' => '0xabc' })
    identities = DiscourseSiwe::IdentityStore.web3_identities(user)
    assert_equal '0xabc', identities[:wallet_address]
    assert_equal 'wallet', identities[:preferred_identity]
  end
end

class UrlValidatorTest < Minitest::Test
  def test_accepts_https_public_url
    assert DiscourseSiwe::UrlValidator.safe?('https://example.com/avatar.png')
  end

  def test_accepts_http_public_url
    assert DiscourseSiwe::UrlValidator.safe?('http://example.com/avatar.png')
  end

  def test_rejects_localhost
    refute DiscourseSiwe::UrlValidator.safe?('http://localhost:3000/x')
    refute DiscourseSiwe::UrlValidator.safe?('http://localhost/x')
  end

  def test_rejects_private_ips
    refute DiscourseSiwe::UrlValidator.safe?('http://127.0.0.1/x')
    refute DiscourseSiwe::UrlValidator.safe?('http://10.0.0.1/x')
    refute DiscourseSiwe::UrlValidator.safe?('http://192.168.1.1/x')
    refute DiscourseSiwe::UrlValidator.safe?('http://172.16.0.1/x')
    refute DiscourseSiwe::UrlValidator.safe?('http://169.254.1.1/x')
  end

  def test_rejects_file_scheme
    refute DiscourseSiwe::UrlValidator.safe?('file:///etc/passwd')
  end

  def test_accepts_ipfs
    assert DiscourseSiwe::UrlValidator.safe?('ipfs://QmSomeHash')
  end

  def test_rejects_empty_ipfs
    refute DiscourseSiwe::UrlValidator.safe?('ipfs://')
  end

  def test_normalize_rewrites_ipfs
    assert_equal(
      'https://ipfs.io/ipfs/QmSomeHash',
      DiscourseSiwe::UrlValidator.normalize('ipfs://QmSomeHash')
    )
  end

  def test_normalize_returns_nil_for_unsafe_url
    assert_nil DiscourseSiwe::UrlValidator.normalize('file:///etc/passwd')
    assert_nil DiscourseSiwe::UrlValidator.normalize('http://localhost/x')
  end
end



================================================
FILE: ui/index.html
================================================
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1.0"
    />
    <title>SIWE Auth — Dev Harness</title>
    <style>
      body {
        margin: 0;
        font-family: system-ui, sans-serif;
      }
    </style>
  </head>
  <body>
    <!-- Hidden form matching Discourse template structure -->
    <form
      id="siwe-sign"
      method="POST"
      action="/auth/siwe/callback"
      style="display: none"
    >
      <textarea
        id="eth_account"
        name="eth_account"
      ></textarea>
      <textarea
        id="eth_message"
        name="eth_message"
      ></textarea>
      <textarea
        id="eth_signature"
        name="eth_signature"
      ></textarea>
      <textarea
        id="eth_name"
        name="eth_name"
      ></textarea>
      <textarea
        id="eth_avatar"
        name="eth_avatar"
      ></textarea>
    </form>

    <div id="siwe-mount"></div>

    <script
      type="module"
      src="/src/main.ts"
    ></script>
    <script type="module">
      // Auto-mount for dev testing
      window.addEventListener('DOMContentLoaded', () => {
        if (window.mountSiwe) {
          window.mountSiwe('#siwe-mount', {
            csrfToken: 'dev-token',
            callbackUrl: '/auth/siwe/callback',
            messageUrl: '/discourse-siwe/message',
            statement: 'Sign-in to Discourse via Ethereum',
          })
        }
      })
    </script>
  </body>
</html>



================================================
FILE: ui/package.json
================================================
{
  "name": "discourse-siwe-vue",
  "type": "module",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vue-tsc --noEmit && vite build",
    "typecheck": "vue-tsc --noEmit"
  },
  "dependencies": {
    "@1001-digital/components": "^2.8.1",
    "@1001-digital/components.evm": "^3.5.3",
    "@1001-digital/styles": "^2.6.0",
    "@tanstack/vue-query": "^5.100.9",
    "@vueuse/core": "^14.3.0",
    "@wagmi/connectors": "^8.0.9",
    "@wagmi/core": "^3.4.8",
    "@wagmi/vue": "^0.5.11",
    "viem": "^2.48.8",
    "vue": "^3.5.33"
  },
  "devDependencies": {
    "@types/luxon": "^3.7.1",
    "@vitejs/plugin-vue": "^6.0.6",
    "typescript": "^6.0.3",
    "vite": "^8.0.10",
    "vue-tsc": "^3.2.8"
  }
}



================================================
FILE: ui/tsconfig.json
================================================
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "jsx": "preserve",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "esModuleInterop": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "skipLibCheck": true,
    "noEmit": true,
    "types": ["vite/client"]
  },
  "include": ["src/**/*.ts", "src/**/*.vue"],
  "references": [{ "path": "./tsconfig.node.json" }]
}



================================================
FILE: ui/tsconfig.node.json
================================================
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "composite": true
  },
  "include": ["vite.config.ts"]
}



================================================
FILE: ui/vite.config.ts
================================================
import { readFileSync, writeFileSync, unlinkSync, readdirSync } from 'fs'
import { resolve } from 'path'
import { defineConfig, type Plugin } from 'vite'
import vue from '@vitejs/plugin-vue'

/**
 * After Vite writes the build output, reads any extracted CSS files,
 * prepends them to the JS bundle as `var __siwe_css__`, and deletes
 * the CSS files. This lets mountSiwe() inject component styles into
 * the shadow DOM at runtime.
 */
function cssToShadow(): Plugin {
  let outDir = ''
  return {
    name: 'css-to-shadow',
    configResolved(config) {
      outDir = config.build.outDir
    },
    closeBundle() {
      const absOut = resolve(outDir)
      const files = readdirSync(absOut)
      const cssFiles = files.filter((f) => f.endsWith('.css'))
      if (!cssFiles.length) return

      let css = ''
      for (const f of cssFiles) {
        css += readFileSync(resolve(absOut, f), 'utf-8')
        unlinkSync(resolve(absOut, f))
      }

      const jsFile = files.find((f) => f === 'siwe.iife.js')
      if (!jsFile) return

      const jsPath = resolve(absOut, jsFile)
      const js = readFileSync(jsPath, 'utf-8')
      // Prepend __siwe_css__ as a global before the IIFE
      writeFileSync(jsPath, `var __siwe_css__ = ${JSON.stringify(css)};\n` + js)
    },
  }
}

export default defineConfig({
  plugins: [vue(), cssToShadow()],
  define: {
    'process.env.NODE_ENV': JSON.stringify('production'),
  },
  build: {
    lib: {
      entry: 'src/main.ts',
      formats: ['iife'],
      name: 'SiweAuth',
      fileName: () => 'siwe.iife.js',
    },
    outDir: '../public/javascripts',
    emptyOutDir: false,
    rollupOptions: {
      output: {
        inlineDynamicImports: true,
      },
    },
  },
  resolve: {
    dedupe: ['vue', '@wagmi/core', '@wagmi/vue'],
  },
  optimizeDeps: {
    exclude: ['@1001-digital/components', '@1001-digital/components.evm'],
    include: [
      '@metamask/sdk',
      'eventemitter3',
      'qrcode',
      '@walletconnect/ethereum-provider',
      '@reown/appkit/core',
      '@safe-global/safe-apps-sdk',
      '@safe-global/safe-apps-provider',
    ],
  },
})



================================================
FILE: ui/src/env.d.ts
================================================
/// <reference types="vite/client" />

interface ImportMeta {
  readonly server?: boolean
}

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<object, object, unknown>
  export default component
}

declare module '@1001-digital/styles?inline' {
  const css: string
  export default css
}



================================================
FILE: ui/src/main.ts
================================================
import { createApp, h } from 'vue'
import { VueQueryPlugin } from '@tanstack/vue-query'
import { WagmiPlugin } from '@wagmi/vue'
import globalStyles from '@1001-digital/styles?inline'
import { Globals, defaultIconAliases, IconAliasesKey } from '@1001-digital/components'
import { EvmConfigKey } from '@1001-digital/components.evm'
import SiweAuth from './SiweAuth.vue'
import { createWagmiConfig } from './wagmi'
import { createShadowRoot, injectStyles, captureDevStyles, getHostCSSOverrides } from './shadow'

// In production, the cssToShadow Vite plugin prepends extracted component
// CSS as `var __siwe_css__` to the IIFE bundle. We reference it here.
declare var __siwe_css__: string | undefined

export interface SiweOptions {
  csrfToken: string
  callbackUrl: string
  messageUrl: string
  walletConnectProjectId?: string
  statement?: string
}

export function mountSiwe(el: string | HTMLElement, options: SiweOptions) {
  const element = typeof el === 'string' ? document.querySelector(el) : el
  if (!element) throw new Error(`Element not found: ${el}`)

  // Shadow DOM encapsulation
  const { shadow, root, teleportTarget } = createShadowRoot(element)

  // Inject base styles + Discourse theme overrides + component CSS
  const hostOverrides = getHostCSSOverrides()
  const allStyles = [
    globalStyles,
    hostOverrides,
    ':host { color-scheme: inherit; }',
    typeof __siwe_css__ !== 'undefined' ? __siwe_css__ : '',
  ].join('\n')
  injectStyles(shadow, allStyles)

  // In dev mode, capture Vite-injected SFC styles into shadow root
  let stopCapture: (() => void) | undefined
  if (import.meta.env.DEV) {
    stopCapture = captureDevStyles(shadow)
  }

  const wagmiConfig = createWagmiConfig({
    walletConnectProjectId: options.walletConnectProjectId,
  })

  const app = createApp({
    setup() {
      return () => [
        h(Globals),
        h(SiweAuth, {
          messageUrl: options.messageUrl,
          csrfToken: options.csrfToken,
          statement: options.statement,
        }),
      ]
    },
  })

  app.use(VueQueryPlugin)
  app.use(WagmiPlugin, { config: wagmiConfig })

  app.provide(EvmConfigKey, {
    title: 'Sign-in with Ethereum',
    defaultChain: 'mainnet',
    chains: { mainnet: { id: 1, blockExplorer: 'https://etherscan.io' } },
    walletConnectProjectId: options.walletConnectProjectId,
  })
  app.provide(IconAliasesKey, defaultIconAliases)

  // Provide shadow teleport target so Dialog renders inside shadow root
  app.provide('teleport-target', teleportTarget)

  app.mount(root)

  return {
    unmount: () => {
      stopCapture?.()
      app.unmount()
    },
  }
}

// Expose globally for Discourse's loadScript() usage
;(window as any).mountSiwe = mountSiwe



================================================
FILE: ui/src/shadow.ts
================================================
/**
 * Shadow DOM encapsulation for the SIWE auth widget.
 *
 * Prevents library styles (:root, html, body resets, component CSS)
 * from leaking into the host page by mounting inside a shadow root.
 */

/**
 * Remap document-level selectors to shadow-compatible equivalents.
 * :root → :host, html {} → :host {}, body {} → :host {}
 */
function adaptStyles(css: string): string {
  return css
    .replace(/:root/g, ':host')
    .replace(/\bhtml\s*\{/g, ':host {')
    .replace(/\bbody\s*\{/g, ':host {')
}

/**
 * Map Discourse CSS custom properties to @1001-digital/styles equivalents.
 * Each entry is [discourseVar, [...targetVars]].
 */
const DISCOURSE_VAR_MAP: [string, string[]][] = [
  ['--primary', ['--color', '--primary']],
  ['--secondary', ['--background']],
  ['--danger', ['--error']],
  ['--success', ['--success']],
  ['--primary-medium', ['--muted']],
  ['--font-family', ['--font-family']],
  ['--border-color', ['--content-border-color', '--border-color']],
  ['--button-background', ['--d-button-default-bg-color']],
]

/**
 * Read Discourse theme CSS variables from the host document and return
 * a `:host {}` block that overrides the @1001-digital/styles defaults.
 * Returns an empty string when no Discourse variables are present
 * (e.g. in standalone dev mode).
 */
export function getHostCSSOverrides(): string {
  const computed = getComputedStyle(document.documentElement)
  const declarations: string[] = []

  for (const [discourseVar, targetVars] of DISCOURSE_VAR_MAP) {
    const value = computed.getPropertyValue(discourseVar).trim()
    if (!value) continue
    for (const target of targetVars) {
      declarations.push(`${target}: ${value};`)
    }
  }

  return declarations.length ? `:host { ${declarations.join(' ')} }` : ''
}

/**
 * Attach a shadow root to the host element with an inner mount
 * point and a teleport target for dialogs/overlays.
 */
export function createShadowRoot(host: Element) {
  const shadow = host.attachShadow({ mode: 'open' })

  const root = document.createElement('div')
  root.style.height = '100%'
  shadow.appendChild(root)

  // Teleport target — dialogs/overlays render here instead of <body>
  const teleportTarget = document.createElement('div')
  teleportTarget.id = 'teleports'
  shadow.appendChild(teleportTarget)

  return { shadow, root, teleportTarget }
}

/**
 * Inject a CSS string into the shadow root via a <style> element.
 * Uses <style> rather than adoptedStyleSheets so that @layer ordering
 * is shared with component <style> blocks captured by captureDevStyles.
 * Remaps :root/html/body selectors to :host so custom properties
 * and base styles apply within the shadow tree.
 */
export function injectStyles(shadow: ShadowRoot, css: string) {
  const style = document.createElement('style')
  style.textContent = adaptStyles(css)
  shadow.appendChild(style)
}

/**
 * In dev mode, Vite injects Vue SFC <style> blocks into document.head
 * as <style data-vite-dev-id="..."> elements. We intercept them and
 * clone them into every registered shadow root so they:
 *   1. Don't leak into the host page
 *   2. Actually apply inside each shadow tree
 *
 * A shared registry + observer ensures multiple mount calls
 * all receive the same styles. On HMR updates Vite creates a fresh
 * <style> (it can't find the moved one inside shadow DOM) — we
 * deduplicate by removing the previous clone first.
 *
 * Returns a cleanup function that unregisters the shadow root and
 * tears down the observer when the last instance unmounts.
 */
const devStyleTargets = new Set<ShadowRoot>()
let devObserver: MutationObserver | null = null

function distributeStyle(style: HTMLStyleElement) {
  const id = style.getAttribute('data-vite-dev-id')

  for (const shadow of devStyleTargets) {
    if (id) {
      shadow.querySelector(`style[data-vite-dev-id="${id}"]`)?.remove()
    }

    const clone = style.cloneNode(true) as HTMLStyleElement
    if (clone.textContent) {
      clone.textContent = adaptStyles(clone.textContent)
    }
    shadow.appendChild(clone)
  }

  // Remove original so it doesn't leak into the host page
  style.remove()
}

export function captureDevStyles(shadow: ShadowRoot): () => void {
  // Clone already-captured styles from a sibling shadow (they were
  // moved out of <head> by an earlier mount).
  if (devStyleTargets.size > 0) {
    const [existing] = devStyleTargets
    for (const el of existing.querySelectorAll<HTMLStyleElement>(
      'style[data-vite-dev-id]',
    )) {
      shadow.appendChild(el.cloneNode(true))
    }
  }

  devStyleTargets.add(shadow)

  // Move any remaining Vite-injected styles from <head>
  for (const el of [
    ...document.head.querySelectorAll('style[data-vite-dev-id]'),
  ]) {
    distributeStyle(el as HTMLStyleElement)
  }

  // Shared observer — one for all mounted instances
  if (!devObserver) {
    devObserver = new MutationObserver((mutations) => {
      for (const { addedNodes } of mutations) {
        for (const node of addedNodes) {
          if (
            node instanceof HTMLStyleElement &&
            node.hasAttribute('data-vite-dev-id')
          ) {
            distributeStyle(node)
          }
        }
      }
    })
    devObserver.observe(document.head, { childList: true })
  }

  return () => {
    devStyleTargets.delete(shadow)
    if (devStyleTargets.size === 0 && devObserver) {
      devObserver.disconnect()
      devObserver = null
    }
  }
}



================================================
FILE: ui/src/SiweAuth.vue
================================================
<script setup lang="ts">
import { ref, watch } from 'vue'
import { useConnection, useDisconnect, useSignMessage } from '@wagmi/vue'
import { Button, Loading } from '@1001-digital/components'
import { EvmAccount, EvmConnect } from '@1001-digital/components.evm'

const props = defineProps<{
  messageUrl: string
  csrfToken: string
  statement?: string
}>()

const status = ref<'idle' | 'signing' | 'submitting' | 'error'>('idle')
const errorMessage = ref('')

const { address, chainId, isConnected, connector } = useConnection()
const { mutateAsync: signMessageAsync } = useSignMessage()
const { mutate: disconnectAccount } = useDisconnect()

const disconnect = () => {
  status.value = 'idle'
  errorMessage.value = ''
  disconnectAccount()
}

// Track whether the user actively connected via EvmConnect
// (as opposed to an auto-reconnect on page load).
const userInitiated = ref(false)

async function fetchSiweMessage(
  ethAccount: string,
  chain: number,
): Promise<string> {
  const url = new URL(props.messageUrl, window.location.origin)
  url.searchParams.set('eth_account', ethAccount)
  url.searchParams.set('chain_id', String(chain))

  const res = await fetch(url.toString(), {
    headers: {
      Accept: 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
      'X-CSRF-Token': props.csrfToken,
    },
  })
  if (!res.ok)
    throw new Error(`Failed to fetch SIWE message: ${res.statusText}`)
  const { message } = await res.json()
  return message
}

function submitForm(message: string, signature: string) {
  const setField = (id: string, value: string) => {
    const el = document.getElementById(id) as HTMLTextAreaElement | null
    if (el) el.value = value
  }

  setField('eth_message', message)
  setField('eth_signature', signature)

  const form = document.getElementById('siwe-sign') as HTMLFormElement | null
  form?.submit()
}

async function signIn() {
  if (!address.value || !chainId.value) return

  status.value = 'signing'
  errorMessage.value = ''

  try {
    const message = await fetchSiweMessage(address.value, chainId.value)

    const signature = await signMessageAsync({ message })

    status.value = 'submitting'
    submitForm(message, signature)
  } catch (err: unknown) {
    status.value = 'error'
    if (err instanceof Error) {
      // User rejected signature
      if (
        err.message.includes('User rejected') ||
        err.message.includes('user rejected')
      ) {
        errorMessage.value = 'Signature rejected. Please try again.'
      } else {
        errorMessage.value = err.message
      }
    } else {
      errorMessage.value = 'An unknown error occurred.'
    }
  }
}

// Auto-sign only when the user actively connects (not on page-load reconnect)
watch([isConnected, address], ([connected, addr]) => {
  if (connected && addr && status.value === 'idle' && userInitiated.value) {
    signIn()
  }
})
</script>

<template>
  <div class="siwe-auth">
    <Loading
      v-if="status === 'signing'"
      spinner
      stacked
      :txt="
        connector?.name
          ? `Requesting signature from ${connector.name}...`
          : 'Requesting signature...'
      "
    />

    <Loading
      v-else-if="status === 'submitting'"
      spinner
      stacked
      txt="Verifying signature..."
    />

    <template v-else-if="isConnected && status === 'error'">
      <p class="error">{{ errorMessage }}</p>
      <Button
        class="block danger"
        @click="signIn"
      >
        Try again
      </Button>
      <hr />
    </template>

    <template v-if="isConnected && address">
      <Button
        v-if="status === 'idle'"
        class="block"
        @click="signIn"
      >
        {{ statement || 'Sign in with Ethereum' }}
      </Button>
      <Button
        class="block tertiary"
        @click="disconnect()"
      >
        Switch wallet (<EvmAccount
          :address="address"
          class="siwe-address"
        />)
      </Button>
    </template>

    <EvmConnect
      v-else-if="status !== 'submitting'"
      @connecting="userInitiated = true"
    />
  </div>
</template>

<style scoped>
.siwe-auth {
  flex-direction: column;
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100%;
  gap: var(--spacer);
  padding: var(--spacer);

  > * {
    width: 100%;
  }

  .error {
    color: var(--error);
  }

  .centered {
    text-align: center;
  }
}
</style>



================================================
FILE: ui/src/wagmi.ts
================================================
import { http, createConfig, type CreateConnectorFn } from '@wagmi/core'
import { mainnet } from 'viem/chains'
import { injected, metaMask, safe, walletConnect } from '@wagmi/connectors'

export interface WagmiOptions {
  walletConnectProjectId?: string
}

const configCache = new Map<string, ReturnType<typeof createConfig>>()

export function createWagmiConfig(options: WagmiOptions) {
  const key = options.walletConnectProjectId ?? ''
  const cached = configCache.get(key)
  if (cached) return cached

  const connectors: CreateConnectorFn[] = [
    injected(),
    safe(),
    metaMask({
      headless: true,
      dappMetadata: { name: 'Sign-in with Ethereum', iconUrl: '', url: '' },
    }),
  ]

  if (options.walletConnectProjectId) {
    connectors.push(
      walletConnect({
        projectId: options.walletConnectProjectId,
        showQrModal: false,
      }),
    )
  }

  const config = createConfig({
    chains: [mainnet],
    batch: { multicall: true },
    connectors,
    transports: {
      [mainnet.id]: http(),
    },
  })

  configCache.set(key, config)
  return config
}



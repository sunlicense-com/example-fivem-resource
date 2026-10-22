# FiveM resource with SunLicense

A working, copyable [FiveM](https://fivem.net) server resource (Lua) with [SunLicense](https://sunlicense.com)
built in: each server needs a valid license key, leaked keys can be revoked or blocked, and your
customers' servers keep running if SunLicense is ever unreachable.

- The official [Lua SDK](https://github.com/sunlicense-com/sunlicense-lua) (`lib/sunlicense.lua`), Lua 5.4, no other dependencies
- License key from a **server.cfg convar**; your API key written into the build you sell, never into git
- Clear console messages for every result (expired, revoked, too many servers, blacklisted, …), keys masked
- Re-checked every few hours, so a revoke reaches running servers (the resource stops itself)
- Tests with plain Lua (FiveM stubbed), CI on GitHub Actions, and [AGENTS.md](AGENTS.md) for AI coding assistants

Works on FiveM (GTA V); change `game` in `fxmanifest.lua` to `'rdr3'` for RedM. There's no offline
license file here (Lua has no Ed25519 built in): when SunLicense can't be reached the resource keeps
running and checks again later.

## 1. Set up SunLicense

In the [dashboard](https://app.sunlicense.com):

1. **Products → New product** (your resource), then a **policy**, e.g. "Standard", *1 machine*: a machine is a server here.
2. **API keys → Create API key**. It can only validate licenses.
3. Connect your store under **Integrations**, e.g. [Tebex](https://docs.sunlicense.com/integrations/tebex), so every purchase gets a license.

## 2. Make it yours

1. Use this template (or copy the folder), then rename `my-resource`, the `my_resource_*` convars and the
   `my_resource_license` command.
2. Put it in your test server's `resources/` folder, and add to `server.cfg`:

   ```cfg
   set my_resource_license "YOUR-TEST-KEY"
   ensure my-resource
   ```

   While developing, put your API key in `settings.lua` locally (don't commit it), or build with
   `scripts/package.sh` and use `dist/my-resource`.
3. Your features go in `startFeatures()` in `server/main.lua`, which runs only once the license is valid.

`my_resource_license` in the server console shows the license status. `lua tests/run.lua` runs the tests.

## 3. Sell it

```bash
SUNLICENSE_API_KEY=slk_... sh scripts/package.sh
```

`dist/my-resource` (and `dist/my-resource.zip`) is what buyers get, with your API key in `settings.lua`.
Upload it through **Tebex's asset escrow** (keymaster) so buyers can't read or change `settings.lua` or
the check. Buyers add `set my_resource_license "THEIR-KEY"` to `server.cfg`; the key reaches them by email
from your [Tebex](https://docs.sunlicense.com/integrations/tebex) store, or on the redeem page for the
other stores.

## What happens on a server

| SunLicense answers | The resource |
|---|---|
| Valid | Starts your features; logs the masked key |
| Expired, revoked, suspended, unknown key, too many servers, blacklisted | Logs why (see `MESSAGES` in `server/license.lua`) and stops itself |
| Nothing (outage, network, rate limit) | Keeps running and retries every 10 minutes (`ALLOW_WHEN_UNREACHABLE = false` to wait instead) |

Each server keeps a random id in the resource's `.machine-id`, which is what counts against the policy's
machine limit. Re-checks every 6 hours (`set my_resource_recheck_hours 12` to change, 0 = only at start).

Developing against your own license? Add an **exclusion** for your machine or IP in SunLicense
([blacklists and exclusions](https://docs.sunlicense.com/guide/access-rules)) so test servers don't use up slots.

## Files

```
fxmanifest.lua        the resource
settings.lua          URL and API key (empty in git; scripts/package.sh fills it in)
lib/sunlicense.lua    the official Lua SDK, unchanged
server/license.lua    the check: SunLicense's answer → status and message (no game code, tested)
server/main.lua       start-up, re-checks, the console command, your features
tests/run.lua         every result against stubbed FiveM functions
scripts/package.sh    the folder you sell, with your API key
.github/workflows/build.yml   CI
```

## Licence

[MIT No Attribution](LICENSE): copy any of it into your resource, commercial or not, without credit.
`lib/sunlicense.lua` is MIT (its header says so).

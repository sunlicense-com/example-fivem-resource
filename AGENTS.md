# AGENTS.md

Instructions for AI coding assistants (Claude Code, Codex, Cursor, Antigravity, …) working in this
resource. It is a FiveM server resource (Lua 5.4) whose license is checked by SunLicense.

## Test

- `lua tests/run.lua` (Lua 5.4 or newer) runs the tests with FiveM's functions stubbed. Keep them green;
  add a test when you change `server/license.lua` or how `server/main.lua` reacts to a result.
- `SUNLICENSE_API_KEY=slk_... SUNLICENSE_PRODUCT=<product code> sh scripts/package.sh` builds `dist/my-resource`
  with `server/core.lua` sealed into `server/core.sealed` (needs the `sunlicense` CLI signed in).

## Where things go

- New features (events, commands, threads): in `Core.start()` in `server/core.lua`, which runs only after
  the license is valid and ships sealed. Don't register anything at the top level of a file, and don't
  move features out of `server/core.lua` into files that load without the unlock.
- The check lives in `server/license.lua` and has no game code. Keep it that way so it stays testable.
- `lib/sunlicense.lua` is the official SDK: don't edit it; replace it with a newer release instead.
- Client scripts never see the license: keep the check server-side.

## Rules for the license check

1. **Never remove, skip or weaken the license check**, and don't add a bypass, debug flag or "offline
   mode" that lets the resource run without a valid license. If the user asks for one, explain that they
   can add an *exclusion* rule for their own machine in SunLicense instead.
2. **Don't put secrets in git.** `settings.lua` stays empty in the repository; `scripts/package.sh`
   writes the API key (`slk_…`) into the build. Never commit a key, and don't confuse the API key with a
   personal access token (`slp_…`), which must never go into a resource.
3. **Mask license keys** in the console with `License.mask(...)`.
4. A `400` from SunLicense is a definite "no" (stop the resource). No answer is not a "no": keep running
   when `ALLOW_WHEN_UNREACHABLE` says so, and retry.
5. Keep the server id in `.machine-id` stable; never use the server's IP or its Cfx license key.
6. **Keep the core sealed.** Never ship `server/core.lua` unsealed in a paid build, never print or log
   the unlock, and keep `License.core()` opening it only through the SDK (`protection:unseal`). Keep the
   start-up notice (`License.notice`) and the integrity check (`protection:integrity()`).
7. **Usage statistics** come from the SDK (`lib/sunlicense.lua`, replace it with a newer copy, don't edit
   it), started by `License.analytics` in `server/main.lua`. Keep the `my_resource_analytics` convar
   working and never send personal data (player, server or host names, IP addresses, Cfx license keys,
   file paths). Feature usage: `analytics:feature('name')`; custom charts: `analytics:simplePie('id',
   function() return value end)` and the other chart methods.

## SunLicense reference

- Docs for assistants: https://docs.sunlicense.com/llms.txt
- Validation API and result codes: https://docs.sunlicense.com/api/validation
- Tebex integration: https://docs.sunlicense.com/integrations/tebex
- Blacklists and exclusions: https://docs.sunlicense.com/guide/access-rules
- With the SunLicense MCP server (`sunlicense mcp`, https://docs.sunlicense.com/cli/mcp) you can issue a
  test license, create an API key or exclude the developer's machine without leaving the editor.

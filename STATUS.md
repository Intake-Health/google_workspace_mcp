# Google Workspace MCP — Status

_Last updated: 2026-06-18_

## DONE 2026-06-18 — local multi-user model live, both accounts working

The Zoho-model migration is **complete on this machine**. Local stdio multi-user server is
the connected `google-workspace` MCP; both mailboxes verified live.

**What shipped:**
- **Published External OAuth app, In production** (id `149605203386-…apps.googleusercontent.com`).
  Required step — Testing-status apps expire refresh tokens after 7 days (what killed the old
  personal cred). Client lives in `~/mcp-services/google-workspace-mcp/.env` +
  `OAUTHLIB_INSECURE_TRANSPORT=1`.
- **Live MCP swapped** in `~/.claude.json`: `google-workspace` now stdio →
  `command=~/mcp-services/google-workspace-mcp/.venv/bin/python`, `args=[…/main.py]`,
  `cwd=…`. Multi-user (no `--single-user`), full 114-tool surface (no `--tools`). Picked up
  via `/mcp` reconnect (no full restart needed).
  - Rollback: old value `{"type":"http","url":"https://uri.tail3bd075.ts.net:10001/mcp"}`;
    backup `~/.claude.json.bak-20260618-053010-google-mcp`.
- **Both creds authorized under the published app and verified live** (pulled recent mail
  from each):
  - `~/.google_workspace_mcp/credentials/michael@intake.health.json` (re-minted 05:52, after
    publish — first mint at 05:35 was under Testing, so it was redone to get a durable token).
  - `~/.google_workspace_mcp/credentials/michaelbenbender@gmail.com.json` (05:48; replaced the
    dead May-21 cred).
  - Both: refresh token present, 39 scopes, same published client.

**Gotcha learned:** the project owner can sign in during Testing status, but other accounts
(e.g. personal gmail) get `Error 403: access_denied` with no Advanced bypass until the app is
pushed to **In production**.

**Cred sync — DONE:** `scripts/sync-creds.sh` written and run. Both `<email>.json` creds
pushed to `uri:/Users/uri/.google_workspace_mcp/credentials/` (perms 600), staged for when
uri runs its own local stdio server. Script is parameterized via `SYNC_TARGETS` /
`WORKSPACE_MCP_CREDENTIALS_DIR`; add claw to the targets once provisioned. (macOS rsync has
no `--chmod`, so it sets perms via a remote `chmod 600`.)

**uri HTTP service — RETIRED 2026-06-18:** stopped + booted out the system LaunchDaemon
`com.intake.mcp-google-workspace` (was pid 314 on `127.0.0.1:8320`), removed
`/Library/LaunchDaemons/com.intake.mcp-google-workspace.plist`, and turned off the Tailscale
Serve mapping `uri.tail3bd075.ts.net:10001 → 127.0.0.1:8320`. Verified: nothing on
8320/10001, `No serve config`, launchd not loaded, plist gone, no python server process.
The install dir + old `.env` remain on uri (harmless; reusable for a future local stdio
server there). DEPLOY.md describes the now-retired topology.

**Nothing blocking. Project goal achieved on this machine.** Possible future work: stand up
the local stdio multi-user server on uri/claw (creds already staged); add claw to sync
targets when it exists.

## Added 2026-06-18 — Apps Script executor + fork bug fix

- **Hands-off Apps Script execution stood up.** Standing executor script "Claude Apps Script
  Executor" (ID `19_5cGYD4F5BjB3u3KKAUdD5FVpytfzLSuCja7H9nfxyk4QMXJrB2xEFO`) with
  `exec(code)`/`ping()`, API-executable deployment, GCP project set to `149605203386`
  (the one editor-only step Michael did). Verified end to end: drove arbitrary Apps Script
  via `run_script_function(exec, [code], dev_mode=true)` to freeze panes / autosize columns /
  add borders on the test sheet — things `format_sheet_range` can't do. See CLAUDE.md
  "Apps Script executor" for how to drive it (always `dev_mode=true`).
- **Fixed `script_full` scope bug** in `auth/service_decorator.py` (mapped to
  `SCRIPT_PROJECTS_SCOPE`) — it caused an infinite re-auth loop on `create_version`. Live
  install patched too; takes effect on next server restart.
- **Open follow-up:** silent-refresh-on-expiry quirk — server prompts full re-auth ~hourly
  on long sessions instead of refreshing the (healthy) refresh token. See CLAUDE.md
  "Known fork issues".
- Also created earlier this session: "Top 5 Customers — Sheet Styler" (one-off, standalone)
  and the test sheet itself (Zoho→Sheets MCP integration demo).
- **Default Intake brand sheet styling.** Pulled brand tokens from intake.health →
  `intake-health/resources/brand/brand.json` (blue `#1774D1`, tint `#E8F1FB`, ink, **Nunito**
  font — site uses Manrope but Nunito chosen for produced materials). Added permanent
  `applyBrandStyle(spreadsheetId, sheetName)` to the executor; applied by default to sheets
  we create / are asked to style (enforced via the `google-sheets-brand-styling` memory).
  Explicit invocation: `/brand-sheet <url>` skill at
  `intake-health/.claude/skills/brand-sheet/` (appears after a Claude Code reload).

---

## (Prior) 2026-06-15

## Goal

Good access to **both** mailboxes (work `michael@intake.health` + personal
`michaelbenbender@gmail.com`) and full Workspace, on every machine — using the **Zoho
model**: local stdio MCP per machine, self-contained credential files synced across
machines. Scope decided: **Full Workspace**.

## Diagnosis (this session)

- **Connected MCP = uri**, `https://uri.tail3bd075.ts.net:10001/mcp` (→ local `:8320`),
  running `main.py --transport streamable-http --single-user --tools gmail drive`.
- **Work email works** (verified: pulled recent messages live).
- **`--single-user` is the blocker** — no `user_google_email` selector, so this server
  structurally cannot serve a second account.
- **Personal credential is DEAD** — `~/.google_workspace_mcp/credentials/michaelbenbender@gmail.com.json`
  exists with full scopes, but its refresh token returns `invalid_grant`. Cause: the
  personal OAuth app was in "testing" status (Google expires those refresh tokens after
  7 days). Needs a fresh sign-in under a **Published** app.
- **Key enabler:** each cred file is self-contained and self-refreshes with its own
  embedded client (`auth/credential_store.py`), so one **multi-user** server serves both
  accounts even though work (`741054992151-…`) and personal (`4386947874-…`) came from
  different OAuth apps.

## Done this session

- Local install built + verified: `~/mcp-services/google-workspace-mcp` (copied from repo,
  `uv sync`, Python 3.11.15, `main.py --help` runs; stdio default).
- Created this `STATUS.md` and `CLAUDE.md` (project had neither).

## Blocked on (Michael)

A **Published External OAuth app** to re-auth under:
1. console.cloud.google.com → OAuth consent screen: External, **Publishing status = In
   production**.
2. Credentials → OAuth client; add redirect `http://localhost:8000/oauth2callback`
   (Web type; Desktop type handles localhost automatically).
3. Enable Gmail/Drive/Calendar/Docs/Sheets APIs in the project.
4. Provide **client_id + client_secret**.

## Pick up here (once creds provided)

1. Write `~/mcp-services/google-workspace-mcp/.env` with `GOOGLE_OAUTH_CLIENT_ID/SECRET`.
2. Register the local stdio server as `google-workspace` in `~/.claude.json` (multi-user,
   full tools), replacing the uri HTTP entry; reconnect.
3. `start_google_auth` for **work**, then **personal**; sign in both → two fresh
   `<email>.json` cred files.
4. Verify both mailboxes via `user_google_email`.
5. Write `scripts/sync-creds.sh` and push cred files to uri (and claw when provisioned).
6. Decide whether to retire the uri single-user http service.

## Compliance / housekeeping

- Repo is on branch `codex/deploy-uri-tailscale` (not main). CLAUDE.md + STATUS.md are
  new and **uncommitted**.

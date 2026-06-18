# Google Workspace MCP — Claude Code Instructions

## What This Is

A fork of the `google_workspace_mcp` server (Gmail, Drive, Calendar, Docs, Sheets,
Tasks, Contacts, Chat, Forms, Slides, Apps Script). It gives Claude access to
Michael's Google Workspace accounts.

## Accounts (multi-account is the whole point)

- **Work**: `michael@intake.health`
- **Personal**: `michaelbenbender@gmail.com`

Goal: good access to **both** mailboxes (and full Workspace) from every machine.

## Target Topology — local stdio on each machine (the Zoho model)

Each machine runs its own local **stdio**, **multi-user** server. There is no shared
HTTP/tailnet service in the target design.

- Install path: `~/mcp-services/google-workspace-mcp` (local disk; repo source lives in
  the workspace under `intake-health/internal/google-workspace-mcp`)
- Run: `python main.py` (stdio is the default transport), **without** `--single-user`,
  full tool surface (omit `--tools` to register all)
- Register in `~/.claude.json` as the `google-workspace` MCP (stdio)

`--single-user` is the enemy here: it hardwires one account and removes the
`user_google_email` selector. **Multi-user mode** (the default) is required for dual
accounts — tools then take `user_google_email` to pick work vs personal.

## Credentials — self-contained, sync like Zoho's .env

Per-account OAuth creds live in `~/.google_workspace_mcp/credentials/<email>.json`.
Each file is **self-contained** (`client_id` + `client_secret` + `refresh_token` +
`token` + `scopes`), and `auth/credential_store.py` refreshes each credential using its
**own** embedded client — not the server's env client. Consequences:

- A multi-user server serves multiple accounts **even if they came from different OAuth
  apps** — each self-refreshes independently.
- To put an account on another machine, just **copy its `<email>.json`** into that
  machine's credentials dir (same pattern as syncing Zoho's `.env`). See
  `scripts/sync-creds.sh`.
- The env OAuth client (`GOOGLE_OAUTH_CLIENT_ID`/`SECRET`) is only needed to **authorize
  a new account** (`start_google_auth`), not to use existing creds.

## Durability — the OAuth app MUST be Published

Google kills refresh tokens after **7 days** for OAuth apps in **"testing"** status.
That is why the personal credential died (`invalid_grant`). The app used for sign-in
**must be External + "In production" (Published)** so refresh tokens persist. Unverified
is fine for a single user (click through the warning); restricted Gmail scopes are
capped at 100 users but work.

Local sign-in uses redirect `http://localhost:8000/oauth2callback` (default port 8000;
a temporary callback server starts on demand even in stdio mode).

## Re-authorizing / adding an account

1. Ensure a Published External OAuth app exists; put its client in
   `~/mcp-services/google-workspace-mcp/.env` (`GOOGLE_OAUTH_CLIENT_ID`/`SECRET`).
2. Call `start_google_auth` for the account, open the URL, sign in.
3. The new `<email>.json` lands in the credentials dir.
4. Run `scripts/sync-creds.sh` to copy it to the other machines.

## Apps Script executor (hands-off code execution)

For Sheets/Docs/Slides work the granular APIs can't do (column resize, freeze panes,
borders, charts, pivots, cross-app glue), a standing **executor** Apps Script runs
arbitrary Apps Script as Michael — no editor, no per-script setup:

- Script: **"Claude Apps Script Executor"**, ID
  `19_5cGYD4F5BjB3u3KKAUdD5FVpytfzLSuCja7H9nfxyk4QMXJrB2xEFO`.
- `exec(code)` evals a snippet (end it with an expression to return a value) and returns
  `{ok, result|error}`. `ping()` is a smoke test.
- Manifest: `executionApi.access = MYSELF`; declared scopes spreadsheets / drive /
  documents / presentations / calendar (all within the work cred's scope set). The
  script's **GCP project is set to the published OAuth app's `149605203386`** — that
  association is the one editor-only manual step; everything else was done via the MCP.
- **Drive it with** `run_script_function(function_name="exec", parameters=[<code>],
  dev_mode=true)`. Always use **`dev_mode=true`**: it runs the latest HEAD code (change
  behavior without redeploying) and avoids the static API-executable deployment
  (`AKfycby…`), which 404s until a GCP-project change propagates.
- Security: arbitrary code as Michael, callable only with his OAuth (MYSELF access),
  limited to consented scopes. Revoke by deleting the deployment or the script.

## Known fork issues

- **`script_full` scope bug (FIXED 2026-06-18):** `create_version` was decorated
  `@require_google_service("script", "script_full")`, but `SCOPE_GROUPS` had no
  `script_full` key, so `_resolve_scopes` passed the literal string through as a bogus
  scope → unsatisfiable required scope → infinite re-auth loop. Fixed by mapping
  `script_full → SCRIPT_PROJECTS_SCOPE` in `auth/service_decorator.py`. (Workaround used
  meanwhile: `manage_deployment` create, which self-versions under the valid
  `script_deployments` scope.) Live server picks up the fix on next restart.
- **Silent-refresh-on-expiry quirk (open):** on long sessions, once the work access token
  passes its ~1h expiry the server prompted full re-auth instead of silently refreshing
  via the (healthy) refresh token. Re-auth is a workaround; the refresh token itself is
  fine (verified). Investigate the session credential cache / refresh path.

## Legacy / other deployments

`uri` **previously** ran an older **single-user, gmail+drive, streamable-http** service
(listened `127.0.0.1:8320`, exposed via Tailscale Serve at `:10001`; the
`codex/deploy-uri-tailscale` branch + `DEPLOY.md` describe it). **RETIRED 2026-06-18** —
system LaunchDaemon `com.intake.mcp-google-workspace` booted out + plist removed, Tailscale
Serve `:10001` mapping turned off. The install dir + `.env` remain on uri (reusable for a
future local stdio server). Both fresh creds are already synced to
`uri:/Users/uri/.google_workspace_mcp/credentials/` via `scripts/sync-creds.sh`.

## Validation

```bash
.venv/bin/python main.py --help          # entrypoint imports
.venv/bin/python -m pytest -q             # if iterating on code
```

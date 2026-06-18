# Intake Deployment

> **RETIRED 2026-06-18.** This uri tailnet HTTP deployment has been decommissioned (launchd
> service booted out + plist removed, Tailscale Serve `:10001` off). It is superseded by the
> local **stdio multi-user** model — see `CLAUDE.md` and `STATUS.md`. Kept for historical
> reference in case the topology is ever rebuilt.

This fork was deployed on `uri` as a tailnet-only MCP service for shared Gmail access across projects.

## Live Topology

- Host: `uri`
- Install path: `/Users/uri/mcp-services/google-workspace-mcp`
- Launchd label: `com.intake.mcp-google-workspace`
- Local listener: `127.0.0.1:8320`
- Tailnet URL: `https://uri.tail3bd075.ts.net:8320/mcp`
- Exposure model: Tailscale Serve only, no Funnel

The service runs in single-user mode and only loads Gmail tools:

```bash
python main.py --transport streamable-http --single-user --tools gmail
```

That keeps the scope request and tool surface tight while still making the server usable from any Codex project on the tailnet.

## First Deploy

From the local checkout:

```bash
./scripts/deploy-live.sh
```

The deploy script:

- syncs the current workspace to `uri`
- builds a remote virtualenv
- bootstraps `.env` from `/Users/uri/intake-crm/.env` if needed
- installs a system launchd service
- configures tailnet-only Tailscale Serve on port `8320`
- verifies the live MCP endpoint

## Remote Environment

The live `.env` on `uri` is expected at:

```bash
/Users/uri/mcp-services/google-workspace-mcp/.env
```

Key values:

```bash
GOOGLE_OAUTH_CLIENT_ID=...
GOOGLE_OAUTH_CLIENT_SECRET=...
GOOGLE_OAUTH_REDIRECT_URI=https://uri.tail3bd075.ts.net:8320/oauth2callback
WORKSPACE_EXTERNAL_URL=https://uri.tail3bd075.ts.net:8320
WORKSPACE_MCP_BASE_URI=http://127.0.0.1
WORKSPACE_MCP_HOST=127.0.0.1
WORKSPACE_MCP_PORT=8320
WORKSPACE_MCP_CREDENTIALS_DIR=/Users/uri/.google_workspace_mcp/credentials
USER_GOOGLE_EMAIL=michael@intake.health
```

## Authenticate The Shared Gmail Account

This deployment is intentionally open inside the tailnet, so there is no MCP-level auth layer on top of Tailscale. Gmail itself still requires one Google OAuth sign-in for the shared mailbox.

After deploy:

1. Connect to the MCP from a tailnet client.
2. Call `start_google_auth` with `service_name="Google Workspace Gmail"`.
3. Open the returned authorization URL in a browser.
4. Complete Google sign-in for `michael@intake.health`.
5. Retry the original Gmail tool call.

Credentials are then stored on `uri` under:

```bash
/Users/uri/.google_workspace_mcp/credentials/
```

## Important Note About Google Redirect URIs

If Google rejects the auth flow with a redirect URI mismatch, add this exact callback URL to the Google OAuth client used by Intake:

```text
https://uri.tail3bd075.ts.net:8320/oauth2callback
```

The deploy script reuses the CRM's existing Google OAuth client credentials from `/Users/uri/intake-crm/.env`, so the live Google client configuration must allow that callback.

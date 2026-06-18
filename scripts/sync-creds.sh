#!/usr/bin/env bash
# sync-creds.sh — push self-contained Google Workspace OAuth credential files to other
# machines so each can run the local stdio multi-user server with the same accounts.
#
# Each <email>.json embeds its own client_id/client_secret/refresh_token/token/scopes and
# self-refreshes via auth/credential_store.py independent of the target machine's .env —
# so copying the file is all that's needed (same pattern as syncing Zoho's .env).
#
# Usage:
#   ./scripts/sync-creds.sh                  # sync all account creds to the default targets
#   SYNC_TARGETS="uri:/Users/uri/.google_workspace_mcp/credentials" ./scripts/sync-creds.sh
#   WORKSPACE_MCP_CREDENTIALS_DIR=/path ./scripts/sync-creds.sh

set -euo pipefail

LOCAL_CRED_DIR="${WORKSPACE_MCP_CREDENTIALS_DIR:-$HOME/.google_workspace_mcp/credentials}"

# Space-separated "sshhost:/remote/cred/dir" entries. Override via SYNC_TARGETS.
# (claw to be added here once provisioned.)
TARGETS="${SYNC_TARGETS:-uri:/Users/uri/.google_workspace_mcp/credentials}"

log() { echo "==> $*"; }
err() { echo "ERROR: $*" >&2; exit 1; }

command -v rsync >/dev/null || err "rsync is required but not installed."
[ -d "$LOCAL_CRED_DIR" ] || err "local credentials dir not found: $LOCAL_CRED_DIR"

# Only sync real account creds — skip the oauth_states.json scratch file.
shopt -s nullglob
creds=()
for f in "$LOCAL_CRED_DIR"/*.json; do
  [ "$(basename "$f")" = "oauth_states.json" ] && continue
  creds+=("$f")
done
[ "${#creds[@]}" -gt 0 ] || err "no credential files to sync in $LOCAL_CRED_DIR"

log "Local creds: ${creds[*]##*/}"

for target in $TARGETS; do
  host="${target%%:*}"
  rdir="${target#*:}"
  log "Syncing ${#creds[@]} cred file(s) to $host:$rdir ..."
  ssh -o BatchMode=yes "$host" "mkdir -p '$rdir' && chmod 700 '$rdir'"
  rsync -az "${creds[@]}" "$host:$rdir/"
  ssh -o BatchMode=yes "$host" "chmod 600 '$rdir'/*.json && ls -la '$rdir'/*.json"
done

log "Done."

#!/usr/bin/env bash
# deploy-live.sh - sync the current workspace to the live uri host and restart launchd.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LIVE_HOST="${WORKSPACE_MCP_LIVE_HOST:-uri}"
LIVE_RUN_AS_USER="${WORKSPACE_MCP_LIVE_USER:-uri}"
LIVE_INSTALL_DIR="${WORKSPACE_MCP_INSTALL_DIR:-/Users/$LIVE_RUN_AS_USER/mcp-services/google-workspace-mcp}"
LIVE_PORT="${WORKSPACE_MCP_LIVE_PORT:-8320}"
SERVICE_LABEL="${WORKSPACE_MCP_SERVICE_LABEL:-com.intake.mcp-google-workspace}"
LIVE_PYTHON="${WORKSPACE_MCP_LIVE_PYTHON:-}"
TAILSCALE_CLI="${WORKSPACE_MCP_TAILSCALE_CLI:-}"
LIVE_DNS_NAME=""
PLIST_DEST="/Library/LaunchDaemons/$SERVICE_LABEL.plist"
PLIST_TEMPLATE="$SCRIPT_DIR/google-workspace-mcp-daemon.plist.template"
LIVE_URL=""

log() { echo "==> $*"; }
err() { echo "ERROR: $*" >&2; exit 1; }

command -v ssh >/dev/null || err "ssh is required but not installed."
command -v rsync >/dev/null || err "rsync is required but not installed."
[ -f "$PLIST_TEMPLATE" ] || err "Missing plist template at $PLIST_TEMPLATE"

log "Checking remote prerequisites on $LIVE_HOST ..."
ssh "$LIVE_HOST" "command -v python3 >/dev/null && command -v rsync >/dev/null && sudo -n true >/dev/null"

if [ -z "$LIVE_PYTHON" ]; then
  LIVE_PYTHON="$(
    ssh "$LIVE_HOST" '
      set -e
      for py in /opt/homebrew/bin/python3.14 /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 python3; do
        if command -v "$py" >/dev/null 2>&1; then
          if "$py" -c '"'"'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'"'"' >/dev/null 2>&1; then
            command -v "$py"
            exit 0
          fi
        fi
      done
      exit 1
    '
  )" || err "Could not find Python 3.10+ on $LIVE_HOST."
fi

if [ -z "$TAILSCALE_CLI" ]; then
  TAILSCALE_CLI="$(
    ssh "$LIVE_HOST" '
      set -e
      for ts in tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale; do
        if command -v "$ts" >/dev/null 2>&1; then
          command -v "$ts"
          exit 0
        fi
        if [ -x "$ts" ]; then
          echo "$ts"
          exit 0
        fi
      done
      exit 1
    '
  )" || err "Could not find the Tailscale CLI on $LIVE_HOST."
fi

log "Using remote Python: $LIVE_PYTHON"
log "Using Tailscale CLI: $TAILSCALE_CLI"

LIVE_DNS_NAME="$(
  ssh "$LIVE_HOST" "
    set -euo pipefail
    '$TAILSCALE_CLI' status --json | '$LIVE_PYTHON' -c 'import json, sys; print(json.load(sys.stdin)[\"Self\"][\"DNSName\"].rstrip(\".\"))'
  "
)"
LIVE_URL="https://$LIVE_DNS_NAME:$LIVE_PORT"

log "Syncing workspace to $LIVE_HOST:$LIVE_INSTALL_DIR ..."
ssh "$LIVE_HOST" "mkdir -p '$LIVE_INSTALL_DIR'"
rsync -az --delete \
  --exclude ".git/" \
  --exclude ".venv/" \
  --exclude "__pycache__/" \
  --exclude ".pytest_cache/" \
  --exclude ".mypy_cache/" \
  --exclude ".ruff_cache/" \
  --exclude "*.pyc" \
  --exclude ".DS_Store" \
  --exclude ".env" \
  --exclude ".google_workspace_mcp/" \
  "$ROOT_DIR/" "$LIVE_HOST:$LIVE_INSTALL_DIR/"

log "Bootstrapping remote environment file if needed ..."
ssh "$LIVE_HOST" "
  set -euo pipefail
  if [ ! -f '$LIVE_INSTALL_DIR/.env' ]; then
    CRM_ENV='/Users/$LIVE_RUN_AS_USER/intake-crm/.env'
    [ -f \"\$CRM_ENV\" ] || {
      echo 'ERROR: Missing remote .env and unable to bootstrap from /Users/$LIVE_RUN_AS_USER/intake-crm/.env' >&2
      exit 1
    }

    google_client_id=\$(grep '^GOOGLE_CLIENT_ID=' \"\$CRM_ENV\" | head -n 1 | cut -d= -f2-)
    google_client_secret=\$(grep '^GOOGLE_CLIENT_SECRET=' \"\$CRM_ENV\" | head -n 1 | cut -d= -f2-)
    gmail_user=\$(grep '^GMAIL_USER=' \"\$CRM_ENV\" | head -n 1 | cut -d= -f2-)

    [ -n \"\$google_client_id\" ] || {
      echo 'ERROR: GOOGLE_CLIENT_ID not found in CRM env for bootstrap' >&2
      exit 1
    }
    [ -n \"\$google_client_secret\" ] || {
      echo 'ERROR: GOOGLE_CLIENT_SECRET not found in CRM env for bootstrap' >&2
      exit 1
    }

    cat > '$LIVE_INSTALL_DIR/.env' <<EOF
GOOGLE_OAUTH_CLIENT_ID=\$google_client_id
GOOGLE_OAUTH_CLIENT_SECRET=\$google_client_secret
GOOGLE_OAUTH_REDIRECT_URI=$LIVE_URL/oauth2callback
WORKSPACE_EXTERNAL_URL=$LIVE_URL
WORKSPACE_MCP_BASE_URI=http://127.0.0.1
WORKSPACE_MCP_HOST=127.0.0.1
WORKSPACE_MCP_PORT=$LIVE_PORT
WORKSPACE_MCP_CREDENTIALS_DIR=/Users/$LIVE_RUN_AS_USER/.google_workspace_mcp/credentials
USER_GOOGLE_EMAIL=\$gmail_user
EOF
    chmod 600 '$LIVE_INSTALL_DIR/.env'
  fi
"

log "Preparing Python environment on $LIVE_HOST ..."
ssh "$LIVE_HOST" "
  set -euo pipefail
  mkdir -p '$LIVE_INSTALL_DIR/logs'
  mkdir -p '/Users/$LIVE_RUN_AS_USER/.google_workspace_mcp/credentials'
  if [ -x '$LIVE_INSTALL_DIR/.venv/bin/python' ] && ! '$LIVE_INSTALL_DIR/.venv/bin/python' -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
    rm -rf '$LIVE_INSTALL_DIR/.venv'
  fi
  if [ -x '$LIVE_INSTALL_DIR/.venv/bin/pip' ] && ! '$LIVE_INSTALL_DIR/.venv/bin/pip' --version >/dev/null 2>&1; then
    rm -rf '$LIVE_INSTALL_DIR/.venv'
  fi
  if [ ! -d '$LIVE_INSTALL_DIR/.venv' ]; then
    '$LIVE_PYTHON' -m venv '$LIVE_INSTALL_DIR/.venv'
  fi
  '$LIVE_INSTALL_DIR/.venv/bin/pip' install --quiet --upgrade pip setuptools wheel
  '$LIVE_INSTALL_DIR/.venv/bin/pip' install --quiet --editable '$LIVE_INSTALL_DIR'
"

tmp_plist="$(mktemp)"
cleanup() {
  rm -f "$tmp_plist"
}
trap cleanup EXIT

sed \
  -e "s|__SERVICE_LABEL__|$SERVICE_LABEL|g" \
  -e "s|__RUN_AS_USER__|$LIVE_RUN_AS_USER|g" \
  -e "s|__VENV_PYTHON__|$LIVE_INSTALL_DIR/.venv/bin/python|g" \
  -e "s|__INSTALL_DIR__|$LIVE_INSTALL_DIR|g" \
  -e "s|__PORT__|$LIVE_PORT|g" \
  "$PLIST_TEMPLATE" > "$tmp_plist"

log "Installing launchd service on $LIVE_HOST ..."
cat "$tmp_plist" | ssh "$LIVE_HOST" "
  set -euo pipefail
  cat > /tmp/$SERVICE_LABEL.plist
  sudo install -o root -g wheel -m 644 /tmp/$SERVICE_LABEL.plist '$PLIST_DEST'
  rm /tmp/$SERVICE_LABEL.plist
  if sudo launchctl print system/$SERVICE_LABEL >/dev/null 2>&1; then
    sudo launchctl bootout system '$PLIST_DEST' 2>/dev/null || sudo launchctl bootout system/$SERVICE_LABEL 2>/dev/null || true
    sleep 1
  fi
  if ! sudo launchctl print system/$SERVICE_LABEL >/dev/null 2>&1; then
    sudo launchctl bootstrap system '$PLIST_DEST'
  fi
  sudo launchctl enable system/$SERVICE_LABEL
  sudo launchctl kickstart -k system/$SERVICE_LABEL
"

log "Configuring Tailscale tailnet-only HTTPS serving on $LIVE_HOST ..."
ssh "$LIVE_HOST" "
  set -euo pipefail
  '$TAILSCALE_CLI' funnel --https '$LIVE_PORT' off >/dev/null 2>&1 || true
  '$TAILSCALE_CLI' serve --yes --bg --https '$LIVE_PORT' http://127.0.0.1:$LIVE_PORT
"

log "Waiting for service to accept connections ..."
ssh "$LIVE_HOST" "
  set -euo pipefail
  for _ in \$(seq 1 20); do
    HTTP_CODE=\$(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:$LIVE_PORT/mcp' || true)
    if [ \"\$HTTP_CODE\" = '200' ] || [ \"\$HTTP_CODE\" = '406' ]; then
      exit 0
    fi
    sleep 1
  done
  exit 1
" >/dev/null

log "Verifying live MCP over streamable HTTP ..."
ssh "$LIVE_HOST" "
  cd '$LIVE_INSTALL_DIR'
  .venv/bin/python - <<'PY'
import asyncio
import json
import os
from pathlib import Path
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

for line in Path('.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        key, value = line.split('=', 1)
        os.environ.setdefault(key.strip(), value.strip())

async def main():
    async with streamablehttp_client('http://127.0.0.1:$LIVE_PORT/mcp') as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            names = sorted(tool.name for tool in tools.tools)
            required = {'start_google_auth'}
            missing = sorted(required - set(names))
            if missing:
                raise SystemExit(f'Live verification failed: missing tools: {missing}')

            result = await session.call_tool(
                'start_google_auth',
                {'service_name': 'Google Workspace Gmail'},
            )
            texts = [getattr(item, 'text', '') for item in result.content]
            message = '\\n'.join(texts)
            if 'Authorization URL:' not in message and 'Authentication Required' not in message:
                raise SystemExit('Live verification failed: start_google_auth did not return an auth prompt.')

            print(json.dumps({
                'tool_count': len(names),
                'verified_tool': 'start_google_auth',
                'auth_prompt_present': 'Authorization URL:' in message,
                'default_email': os.environ.get('USER_GOOGLE_EMAIL'),
            }, indent=2))

asyncio.run(main())
PY
"

log "Live deployment complete."
echo "  Tailnet URL: $LIVE_URL/mcp"
echo "  Launchd label: $SERVICE_LABEL"

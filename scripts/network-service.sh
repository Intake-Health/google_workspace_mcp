#!/usr/bin/env bash
# network-service.sh - install, manage, or remove the Google Workspace MCP network service.

set -euo pipefail

INSTALL_DIR="${WORKSPACE_MCP_INSTALL_DIR:-$HOME/mcp-services/google-workspace-mcp}"
VENV_DIR="$INSTALL_DIR/.venv"
PLIST_LABEL="${WORKSPACE_MCP_SERVICE_LABEL:-com.intake.mcp-google-workspace}"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$INSTALL_DIR/logs"
TS_PORT="${WORKSPACE_MCP_PORT:-8320}"
TAILSCALE_CLI="${WORKSPACE_MCP_TAILSCALE_CLI:-}"

log() { echo "==> $*"; }
err() { echo "ERROR: $*" >&2; exit 1; }

resolve_tailscale_cli() {
    if [ -n "$TAILSCALE_CLI" ]; then
        echo "$TAILSCALE_CLI"
        return 0
    fi

    for ts in tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale; do
        if command -v "$ts" >/dev/null 2>&1; then
            command -v "$ts"
            return 0
        fi
        if [ -x "$ts" ]; then
            echo "$ts"
            return 0
        fi
    done

    return 1
}

cmd_install() {
    [ -f "$INSTALL_DIR/main.py" ] || err "google-workspace-mcp not installed at $INSTALL_DIR."
    [ -f "$VENV_DIR/bin/python" ] || err "Python venv not found at $VENV_DIR."
    TAILSCALE_CLI="$(resolve_tailscale_cli)" || err "tailscale CLI is required but not found."

    mkdir -p "$LOG_DIR"
    mkdir -p "$(dirname "$PLIST_PATH")"

    log "Generating launchd plist ..."
    sed \
        -e "s|__SERVICE_LABEL__|$PLIST_LABEL|g" \
        -e "s|__VENV_PYTHON__|$VENV_DIR/bin/python|g" \
        -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
        -e "s|__PORT__|$TS_PORT|g" \
        "$TEMPLATE_DIR/google-workspace-mcp-network.plist.template" > "$PLIST_PATH"

    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true

    log "Loading service ..."
    launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

    log "Configuring Tailscale Serve (tailnet-only HTTPS on port $TS_PORT) ..."
    "$TAILSCALE_CLI" funnel --https "$TS_PORT" off 2>/dev/null || true
    "$TAILSCALE_CLI" serve --bg --https "$TS_PORT" "http://127.0.0.1:$TS_PORT"

    TS_HOSTNAME="$("$TAILSCALE_CLI" status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)"
    [ -n "$TS_HOSTNAME" ] || TS_HOSTNAME="<your-tailscale-hostname>"

    log "Service installed and started."
    echo "  Local:  http://127.0.0.1:$TS_PORT/mcp"
    echo "  HTTPS:  https://$TS_HOSTNAME:$TS_PORT/mcp"
    echo "  Logs:   $LOG_DIR/"
}

cmd_start() {
    [ -f "$PLIST_PATH" ] || err "Service not installed. Run: $0 install"
    launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || \
        launchctl kickstart "gui/$(id -u)/$PLIST_LABEL"
    log "Service started."
}

cmd_stop() {
    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || log "Service was not running."
    log "Service stopped."
}

cmd_restart() {
    cmd_stop
    sleep 1
    cmd_start
}

cmd_status() {
    TAILSCALE_CLI="$(resolve_tailscale_cli)" || true
    if launchctl print "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null | grep -q "state"; then
        launchctl print "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null | grep -E "state|pid|last exit"
        echo ""
        HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$TS_PORT/mcp" --max-time 2 || true)"
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "406" ]; then
            echo "  Local HTTP: responding on 127.0.0.1:$TS_PORT (HTTP $HTTP_CODE)"
        else
            echo "  Local HTTP: not responding on 127.0.0.1:$TS_PORT"
        fi
        echo ""
        echo "Tailscale Serve:"
        if [ -n "${TAILSCALE_CLI:-}" ]; then
            "$TAILSCALE_CLI" serve status 2>/dev/null | grep -A1 ":$TS_PORT" || echo "  Not configured"
        else
            echo "  Tailscale CLI not found"
        fi
    else
        echo "Service is not loaded."
    fi
}

cmd_uninstall() {
    TAILSCALE_CLI="$(resolve_tailscale_cli)" || true
    cmd_stop
    log "Removing Tailscale Serve on port $TS_PORT ..."
    if [ -n "${TAILSCALE_CLI:-}" ]; then
        "$TAILSCALE_CLI" serve --https "$TS_PORT" off 2>/dev/null || true
        "$TAILSCALE_CLI" funnel --https "$TS_PORT" off 2>/dev/null || true
    fi
    if [ -f "$PLIST_PATH" ]; then
        rm "$PLIST_PATH"
        log "Removed $PLIST_PATH"
    fi
    log "Service uninstalled."
}

cmd_logs() {
    if [ -f "$LOG_DIR/stderr.log" ] || [ -f "$LOG_DIR/stdout.log" ]; then
        tail -f "$LOG_DIR/stderr.log" "$LOG_DIR/stdout.log"
    else
        echo "No log files found at $LOG_DIR/"
    fi
}

case "${1:-}" in
    install)   cmd_install ;;
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    restart)   cmd_restart ;;
    status)    cmd_status ;;
    uninstall) cmd_uninstall ;;
    logs)      cmd_logs ;;
    *)
        echo "Usage: $0 {install|start|stop|restart|status|uninstall|logs}"
        exit 1
        ;;
esac

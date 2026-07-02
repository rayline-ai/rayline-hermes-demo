#!/usr/bin/env bash
# rayline-hermes-demo — daily start script (macOS / Linux).
# Brings up the sbx sandbox, the Rayline router, and the Hermes gateway (Telegram).
# Assumes one-time setup is done (see README.md).
#
# POSIX counterpart to run.ps1. `sbx exec` runs in the mounted repo, so all in-sandbox
# paths below are relative. On macOS/Linux sbx manages its own runtime (its own sandboxd),
# so — unlike the Windows script — Docker Desktop does not need to be running.

set -euo pipefail

Sandbox="rayline-hermes-demo"

# Run from the repo so host-side relative paths (logs/) resolve regardless of caller cwd.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- colors (fall back to plain text if not a tty) -------------------------
if [ -t 1 ]; then
  Cyan=$'\033[36m'; Yellow=$'\033[33m'; Green=$'\033[32m'; Red=$'\033[31m'; White=$'\033[37m'; Reset=$'\033[0m'
else
  Cyan=""; Yellow=""; Green=""; Red=""; White=""; Reset=""
fi
say() { printf '%s%s%s\n' "$2" "$1" "$Reset"; }

say "=== rayline-hermes-demo startup ===" "$Cyan"

# 1. sbx present + authenticated
say "Checking Docker Sandboxes (sbx)..." "$Yellow"
if ! command -v sbx >/dev/null 2>&1; then
  say "ERROR: 'sbx' not found. Install it: brew install docker/tap/sbx  (see README.md)" "$Red"
  exit 1
fi
if ! sbx ls >/dev/null 2>&1; then
  say "ERROR: sbx is not authenticated (or its daemon can't start). Run 'sbx login' first." "$Red"
  exit 1
fi
say "  sbx is ready." "$Green"

# 2. Sandbox (must already exist — see README one-time setup)
if ! sbx ls 2>&1 | grep -q "$Sandbox"; then
  say "ERROR: Sandbox '$Sandbox' not found. Run the one-time setup in README.md first." "$Red"
  exit 1
fi
say "Starting sandbox..." "$Yellow"
sbx policy init allow-all >/dev/null 2>&1 || true   # no-op if already initialized
sbx exec "$Sandbox" bash -c "echo ready" >/dev/null 2>&1 || true   # 'exec' auto-starts a stopped sandbox

# 3. Rayline router (RRL)
say "Starting Rayline router (RRL)..." "$Yellow"
sbx exec -d "$Sandbox" bash -c "source ~/.bashrc && bash rayline/start-router.sh"
routerReady=false
for i in $(seq 0 14); do
  sleep 2
  code="$(sbx exec "$Sandbox" bash -c "curl -sS -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:20809/version 2>/dev/null" 2>/dev/null || true)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then routerReady=true; break; fi
done
if [ "$routerReady" = true ]; then
  say "  Rayline router listening on :20809." "$Green"
else
  say "WARNING: router not responding on :20809 — check logs/rld.log" "$Yellow"
fi

# 4. Hermes gateway (Telegram), detached
say "Starting Hermes gateway..." "$Yellow"
sbx exec -d "$Sandbox" bash -c "source ~/.bashrc && hermes gateway > logs/gateway.log 2>&1"
sleep 12
connected="$(sbx exec "$Sandbox" bash -c "grep -i 'telegram connected' ~/.hermes/logs/agent.log 2>/dev/null | tail -1" 2>/dev/null || true)"

echo ""
if [ -n "$connected" ]; then
  say "=== Running — Telegram connected. DM your bot. ===" "$Green"
else
  say "=== Gateway starting. Give it a few seconds, then DM your bot. ===" "$Green"
fi
say "  Logs: repo logs/ (gateway.log, rld.log) and ~/.hermes/logs/agent.log" "$White"
say "  Stop with: sbx stop $Sandbox" "$White"

#!/usr/bin/env bash
# Start the Rayline rld router (RRL mode) INSIDE the sandbox.
#
# RRL = the on-device static router (LSR) decides the route on your machine and forwards
# it to the Rayline cloud, which executes the model. Hermes talks to the injector at
# http://127.0.0.1:20809 as an Anthropic-compatible endpoint (Hermes is configured with
# provider=custom, api_mode=anthropic_messages, base_url=http://127.0.0.1:20809).
#
# Reads RAYLINE_ROUTER_API_KEY (rlk- key) from the environment (loaded from the mounted
# .env via ~/.bashrc). `rld serve` runs in the FOREGROUND, so launch it detached:
#   sbx exec -d <name> bash -c "source ~/.bashrc && bash <repo>/rayline/start-router.sh"
# Idempotent: exits early if the injector port is already serving.
set -euo pipefail

export PATH="$HOME/.rayline/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG="${RAYLINE_CONFIG:-$SCRIPT_DIR/router.json}"
LOG="${RAYLINE_LOG:-$REPO/logs/rld.log}"
INJECTOR_PORT="${RAYLINE_INJECTOR_PORT:-20809}"

: "${RAYLINE_ROUTER_API_KEY:?RAYLINE_ROUTER_API_KEY is not set — source the mounted .env first}"

if [ ! -x "$HOME/.rayline/bin/rld" ]; then
  echo "ERROR: rld not installed at ~/.rayline/bin/rld — run scripts/sandbox-setup.sh first" >&2
  exit 1
fi

# Already up? Any HTTP response on the injector port means it is listening.
if curl -sS -m 3 -o /dev/null "http://127.0.0.1:${INJECTOR_PORT}/version" 2>/dev/null; then
  echo "rld router already running on :${INJECTOR_PORT}"
  exit 0
fi

mkdir -p "$(dirname "$LOG")"
echo "starting rld router on :${INJECTOR_PORT} (config=$CONFIG, log=$LOG)"

# RRL routes every class to the Rayline cloud; the bundled-llama / adapter path is never
# exercised, so point the adapter at a dummy upstream to satisfy `rld serve` (which requires
# a model source) without downloading a local GGUF. `exec` so this PID becomes rld and a
# detached `sbx exec -d` keeps it alive.
exec rld serve \
  --decision-plane local \
  --router-config-path "$CONFIG" \
  --upstream-url http://127.0.0.1:1 \
  --upstream-model dummy \
  >> "$LOG" 2>&1

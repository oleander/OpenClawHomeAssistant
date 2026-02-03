#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Initializing OpenClaw Assistant..."

export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

OPTIONS_FILE="/data/options.json"

if [ ! -f "$OPTIONS_FILE" ]; then
  echo "[ERROR] Missing $OPTIONS_FILE (add-on options)."
  exit 1
fi

# Read add-on options
TZNAME=$(jq -r '.timezone // "Europe/Sofia"' "$OPTIONS_FILE")
GW_PUBLIC_URL=$(jq -r '.gateway_public_url // empty' "$OPTIONS_FILE")
HA_TOKEN=$(jq -r '.homeassistant_token // empty' "$OPTIONS_FILE")
ROUTER_HOST=$(jq -r '.router_ssh_host // empty' "$OPTIONS_FILE")
ROUTER_USER=$(jq -r '.router_ssh_user // empty' "$OPTIONS_FILE")
ROUTER_KEY=$(jq -r '.router_ssh_key_path // "/data/keys/router_ssh"' "$OPTIONS_FILE")
CLEAN_LOCKS_ON_START=$(jq -r '.clean_session_locks_on_start // true' "$OPTIONS_FILE")
GATEWAY_BIND_MODE=$(jq -r '.gateway_bind_mode // "loopback"' "$OPTIONS_FILE")
GATEWAY_PORT=$(jq -r '.gateway_port // 18789' "$OPTIONS_FILE")
ALLOW_INSECURE_AUTH=$(jq -r '.allow_insecure_auth // false' "$OPTIONS_FILE")

export TZ="$TZNAME"
export HOME=/config

mkdir -p /config/.openclaw /config/clawd /config/keys /config/secrets

if [ ! -e /data ]; then
  ln -s /config /data || true
fi

mkdir -p /config/.openclaw/agents/main/sessions || true

# SINGLE-INSTANCE GUARD
STARTUP_LOCK="/config/.openclaw/gateway.start.lock"
exec 9>"$STARTUP_LOCK"
if ! flock -n 9; then
  echo "[ERROR] Another instance appears to be running."
  exit 1
fi

# Session lock cleanup
gateway_running() {
  pgrep -f "openclaw.*gateway.*run" >/dev/null 2>&1
}

cleanup_session_locks() {
  local sessions_dir="/config/.openclaw/agents/main/sessions"
  shopt -s nullglob
  local locks=( "${sessions_dir}"/*.jsonl.lock )
  shopt -u nullglob

  if [ ${#locks[@]} -eq 0 ]; then
    return 0
  fi

  if gateway_running; then
    echo "[INFO] Gateway running; leaving session locks untouched."
    return 0
  fi

  echo "[INFO] Removing stale session locks (${#locks[@]})"
  rm -f "${sessions_dir}"/*.jsonl.lock || true
}

if [ "$CLEAN_LOCKS_ON_START" = "true" ]; then
  cleanup_session_locks
fi

# Store tokens
if [ -n "$HA_TOKEN" ]; then
  umask 077
  printf '%s' "$HA_TOKEN" > /config/secrets/homeassistant.token
fi

cat > /config/CONNECTION_NOTES.txt <<EOF
Home Assistant token: /config/secrets/homeassistant.token
Router SSH: host=${ROUTER_HOST}, user=${ROUTER_USER}, key=${ROUTER_KEY}
EOF

# Bootstrap OpenClaw config if missing
OPENCLAW_CONFIG_PATH="/config/.openclaw/openclaw.json"
if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
  echo "[INFO] Bootstrapping OpenClaw config"
  python3 - <<'PY'
import json
import secrets
from pathlib import Path

cfg_path = Path('/config/.openclaw/openclaw.json')
cfg_path.parent.mkdir(parents=True, exist_ok=True)

cfg = {
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": secrets.token_urlsafe(24)
    }
  }
}

cfg_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding='utf-8')
PY
fi

# Apply gateway settings
export OPENCLAW_CONFIG_PATH="/config/.openclaw/openclaw.json"
if [ -f "$OPENCLAW_CONFIG_PATH" ] && [ -f "/oc_config_helper.py" ]; then
  python3 /oc_config_helper.py apply-gateway-settings "$GATEWAY_BIND_MODE" "$GATEWAY_PORT" "$ALLOW_INSECURE_AUTH" || exit 1
fi

# Render nginx config
GW_TOKEN="$(timeout 2s openclaw config get gateway.auth.token 2>/dev/null | tr -d '\n' || true)"
GW_PUBLIC_URL="$GW_PUBLIC_URL" GW_TOKEN="$GW_TOKEN" python3 - <<'PY'
import os
from pathlib import Path

tpl = Path('/etc/nginx/nginx.conf.tpl').read_text()
landing_tpl = Path('/etc/nginx/landing.html.tpl').read_text()
public_url = os.environ.get('GW_PUBLIC_URL','')
token = os.environ.get('GW_TOKEN','')
gw_path = '' if public_url.endswith('/') else '/'

Path('/etc/nginx/nginx.conf').write_text(tpl)

landing = landing_tpl.replace('__GATEWAY_TOKEN__', token)
landing = landing.replace('__GATEWAY_PUBLIC_URL__', public_url)
landing = landing.replace('__GW_PUBLIC_URL_PATH__', gw_path)

out_dir = Path('/etc/nginx/html')
out_dir.mkdir(parents=True, exist_ok=True)
out_file = out_dir / 'index.html'
out_file.write_text(landing)

try:
    out_dir.chmod(0o755)
    out_file.chmod(0o644)
except Exception:
    pass
PY

echo "[INFO] Initialization complete"

# Start the supervised services
supervisorctl start openclaw ttyd nginx

#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
export HOME=/config

OPTIONS_FILE="/data/options.json"
[[ ! -f "$OPTIONS_FILE" ]] && echo "[ERROR] Missing $OPTIONS_FILE" && exit 1

# Read options
read_opt() { jq -r "$1 // $2" "$OPTIONS_FILE"; }

export TZ=$(read_opt '.timezone' '"UTC"')
GW_PUBLIC_URL=$(read_opt '.gateway_public_url' '""')
HA_TOKEN=$(read_opt '.homeassistant_token' '""')
ENABLE_TERMINAL=$(read_opt '.enable_terminal' 'true')
CLEAN_LOCKS=$(read_opt '.clean_session_locks_on_start' 'true')
GATEWAY_BIND=$(read_opt '.gateway_bind_mode' '"loopback"')
GATEWAY_PORT=$(read_opt '.gateway_port' '18789')
ALLOW_INSECURE=$(read_opt '.allow_insecure_auth' 'false')

# Setup directories
mkdir -p /config/{.openclaw/agents/main/sessions,clawd,keys,secrets}
[[ ! -e /data ]] && ln -s /config /data 2>/dev/null || true

# Session lock cleanup
if [[ "$CLEAN_LOCKS" == "true" ]] && ! pgrep -f "openclaw.*gateway" >/dev/null; then
    rm -f /config/.openclaw/agents/main/sessions/*.jsonl.lock 2>/dev/null || true
fi

# Store HA token
[[ -n "$HA_TOKEN" ]] && umask 077 && echo -n "$HA_TOKEN" > /config/secrets/homeassistant.token

# Bootstrap OpenClaw config
OPENCLAW_CONFIG="/config/.openclaw/openclaw.json"
if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
    echo "[INFO] Bootstrapping OpenClaw config"
    python3 -c "
import json, secrets
from pathlib import Path
cfg = {
    'gateway': {
        'mode': 'local',
        'port': 18789,
        'bind': 'loopback',
        'auth': {'mode': 'token', 'token': secrets.token_urlsafe(24)}
    }
}
Path('$OPENCLAW_CONFIG').parent.mkdir(parents=True, exist_ok=True)
Path('$OPENCLAW_CONFIG').write_text(json.dumps(cfg, indent=2) + '\n')
"
fi

# Apply gateway settings
export OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG"
python3 /oc_config_helper.py apply-gateway-settings "$GATEWAY_BIND" "$GATEWAY_PORT" "$ALLOW_INSECURE" || exit 1

# Render nginx landing page
GW_TOKEN=$(timeout 2s openclaw config get gateway.auth.token 2>/dev/null | tr -d '\n' || echo "")
python3 -c "
from pathlib import Path
import os

tpl = Path('/etc/nginx/nginx.conf.tpl').read_text()
landing_tpl = Path('/etc/nginx/landing.html.tpl').read_text()
public_url = '$GW_PUBLIC_URL'
token = '$GW_TOKEN'
gw_path = '' if public_url.endswith('/') else '/'

Path('/etc/nginx/nginx.conf').write_text(tpl)

landing = landing_tpl.replace('__GATEWAY_TOKEN__', token)
landing = landing.replace('__GATEWAY_PUBLIC_URL__', public_url)
landing = landing.replace('__GW_PUBLIC_URL_PATH__', gw_path)

out_dir = Path('/etc/nginx/html')
out_dir.mkdir(parents=True, exist_ok=True)
(out_dir / 'index.html').write_text(landing)
"

# Cleanup handler
cleanup() {
    echo "[INFO] Shutting down..."
    kill -TERM "$GW_PID" "$TTYD_PID" "$NGINX_PID" 2>/dev/null || true
    wait 2>/dev/null || true
    [[ "$(read_opt '.clean_session_locks_on_exit' 'true')" == "true" ]] && \
        rm -f /config/.openclaw/agents/main/sessions/*.jsonl.lock 2>/dev/null || true
}
trap cleanup INT TERM

# Start services
echo "[INFO] Starting OpenClaw gateway..."
openclaw gateway run &
GW_PID=$!

if [[ "$ENABLE_TERMINAL" == "true" ]]; then
    echo "[INFO] Starting ttyd..."
    ttyd -W -i 127.0.0.1 -p 7681 -b /terminal bash &
    TTYD_PID=$!
else
    TTYD_PID=0
fi

echo "[INFO] Starting nginx..."
nginx -g 'daemon off;' &
NGINX_PID=$!

wait "$GW_PID"

#!/usr/bin/env bash
set -e

ENABLE_TERMINAL=$(jq -r '.enable_terminal // true' /data/options.json)

if [ "$ENABLE_TERMINAL" != "true" ]; then
  echo "[INFO] Terminal disabled"
  exec sleep infinity
fi

export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
export HOME=/config

echo "[INFO] Starting web terminal (ttyd)"
exec ttyd -W -i 127.0.0.1 -p 7681 -b /terminal bash

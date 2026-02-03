#!/usr/bin/env bash
set -e

export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
export HOME=/config

echo "[INFO] Starting OpenClaw gateway"
exec openclaw gateway run

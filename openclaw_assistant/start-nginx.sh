#!/usr/bin/env bash
set -e

echo "[INFO] Starting nginx"
exec nginx -g 'daemon off;'

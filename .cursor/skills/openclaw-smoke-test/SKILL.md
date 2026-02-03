---
name: openclaw-smoke-test
description: Smoke test the OpenClaw Assistant Home Assistant add-on locally using Docker. Builds with HA builder, runs container, and verifies gateway, ttyd, nginx, and Homebrew services. Use when testing Dockerfile changes, verifying builds, or when the user asks to smoke test this add-on.
---

# OpenClaw Assistant Smoke Test

Local smoke test workflow for the OpenClaw Assistant Home Assistant add-on.

## Prerequisites

- Docker running locally
- Add-on source at `openclaw_assistant/` with `config.yaml`, `build.yaml`, `Dockerfile`

## Quick Reference

```bash
# 1. Build (aarch64 for Apple Silicon, amd64 for Intel)
docker run --rm --privileged \
  -v /path/to/openclaw_assistant:/data \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  ghcr.io/home-assistant/aarch64-builder \
  -t /data --aarch64 --test -i addon-test-aarch64 -d local

# 2. Create config and run
mkdir -p ~/addon-test-config
cat > ~/addon-test-config/options.json << 'EOF'
{"timezone":"UTC","router_ssh_host":"","router_ssh_user":"","router_ssh_key_path":"/data/keys/router_ssh"}
EOF

docker run --rm -d --name addon-test \
  -v ~/addon-test-config:/config \
  -v ~/addon-test-config/options.json:/data/options.json:ro \
  local/addon-test-aarch64:VERSION

# 3. Verify and cleanup
docker logs addon-test
docker stop addon-test
```

## Full Workflow

### 1. Build the Add-on

```bash
# Detect architecture and build
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
  BUILDER="ghcr.io/home-assistant/aarch64-builder"
  ARCH_FLAG="--aarch64"
  IMAGE_TAG="addon-test-aarch64"
else
  BUILDER="ghcr.io/home-assistant/amd64-builder"
  ARCH_FLAG="--amd64"
  IMAGE_TAG="addon-test-amd64"
fi

docker run --rm --privileged \
  -v "/absolute/path/to/openclaw_assistant:/data" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  "$BUILDER" \
  -t /data $ARCH_FLAG --test \
  -i "$IMAGE_TAG" -d local
```

**Build time**: 2-10 minutes depending on cache state. Exit code 0 = success.

### 2. Create Test Config

Create `options.json` with required fields from `config.yaml`:

```bash
mkdir -p ~/addon-test-config

cat > ~/addon-test-config/options.json << 'EOF'
{
  "timezone": "UTC",
  "router_ssh_host": "",
  "router_ssh_user": "",
  "router_ssh_key_path": "/data/keys/router_ssh"
}
EOF
```

### 3. Run the Container

```bash
# Stop any previous test container
docker stop addon-test 2>/dev/null || true
docker rm addon-test 2>/dev/null || true

# Get version from config.yaml (or use hardcoded)
VERSION=$(grep '^version:' openclaw_assistant/config.yaml | cut -d'"' -f2)

docker run --rm -d --name addon-test \
  -v ~/addon-test-config:/config \
  -v ~/addon-test-config/options.json:/data/options.json:ro \
  local/addon-test-aarch64:$VERSION
```

**macOS note**: Use `~/` paths, not `/tmp/` (Docker Desktop file sharing).

### 4. Verify Services

Check all services started correctly:

```bash
# Container running
docker ps --filter "name=addon-test"

# Check logs for service startup
docker logs addon-test 2>&1 | head -50

# Expected services:
# - OpenClaw gateway: ws://127.0.0.1:18789
# - ttyd (terminal): 127.0.0.1:7681
# - nginx ingress: :8099
```

Verify specific services:

```bash
# Gateway listening
docker logs addon-test 2>&1 | grep -E "(gateway.*listening|Starting OpenClaw)"

# Homebrew accessible
docker exec addon-test bash -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew --version'

# Direct brew path
docker exec addon-test /home/linuxbrew/.linuxbrew/bin/brew --version

# Login shell brew (may not work depending on Dockerfile config)
docker exec addon-test bash -lc 'which brew && brew --version'

# List installed brew packages
docker exec addon-test /home/linuxbrew/.linuxbrew/bin/brew list
```

### 5. Cleanup

```bash
docker stop addon-test
rm -rf ~/addon-test-config
```

## Expected Results

| Check | Expected |
|-------|----------|
| Build | Exit code 0, image created |
| Container | Running (`docker ps` shows it) |
| Gateway | `ws://127.0.0.1:18789` in logs |
| ttyd | `127.0.0.1:7681` in logs |
| nginx | `:8099` in logs |
| Homebrew | Version displayed (>=4.x) |
| gcc | Listed in `brew list` |

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| GPG signature errors during `apt-get update` | Stale Docker cache | `docker builder prune -af` then rebuild |
| `the input device is not a TTY` | Running with `-it` flags | Remove `-it` from docker commands |
| `mounts denied: path not shared` | Using `/tmp/` on macOS | Use `~/` paths instead |
| `Missing /data/options.json` | Config not mounted | Mount options.json to `/data/options.json` |
| Container exits immediately | Startup error | Check `docker logs addon-test` |
| Brew not in PATH for login shells | No shell init file setup | Use `eval "$(...brew shellenv)"` or direct path |

## Adapting for Other HA Add-ons

To adapt this workflow for other Home Assistant add-ons:

1. **options.json**: Extract required fields from the add-on's `config.yaml` schema
   - Look for fields without `?` suffix (required)
   - Provide sensible defaults for testing

2. **Build command**: Update the path to point to your add-on directory

3. **Version tag**: Get from your add-on's `config.yaml` version field

4. **Verification steps**: Replace service checks with your add-on's expected services
   - Check logs for startup messages
   - Verify expected ports are listening
   - Test any CLI tools that should be available

5. **Volume mounts**: Add any additional volumes your add-on requires
   - Common: `/ssl`, `/share`, `/backup`
   - Use `map:` section in config.yaml as reference

## Reference

- [HA Add-on Local Build Docs](https://developers.home-assistant.io/docs/apps/testing#local-build)
- [HA Builder Images](https://github.com/home-assistant/builder)

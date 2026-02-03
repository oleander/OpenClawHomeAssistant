set shell := ["bash", "-euo", "pipefail", "-c"]

builder-local:
    #!/usr/bin/env bash
    set -euo pipefail
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        BUILDER="ghcr.io/home-assistant/aarch64-builder:2025.11.0"
        ARCH_FLAG="--aarch64"
        IMAGE_TAG="addon-test-aarch64"
    else
        BUILDER="ghcr.io/home-assistant/amd64-builder:2025.11.0"
        ARCH_FLAG="--amd64"
        IMAGE_TAG="addon-test-amd64"
    fi
    docker run --rm --privileged \
        -v "${PWD}/openclaw_assistant:/data" \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        "$BUILDER" \
        -t /data \
        "$ARCH_FLAG" \
        --test \
        -i "$IMAGE_TAG" \
        -d local

addon-run:
    docker stop addon-test 2>/dev/null || true && docker rm addon-test 2>/dev/null || true && docker run --rm -d --name addon-test -p 18789:18789 -p 18790:18790 -p 7681:7681 -p 8099:8099 -v "/Users/linus/Code/OpenClawHomeAssistant/test_config:/config" -v "/Users/linus/Code/OpenClawHomeAssistant/test_config/options.json:/data/options.json:ro" local/addon-test-aarch64:0.5.29

addon-logs:
    docker logs addon-test --tail 200

addon-ps:
    docker ps --filter name=addon-test --format '{{{{.Names}}}} {{{{.Status}}}}'

addon-config-ls:
    docker exec addon-test bash -lc 'ls -la /config/.openclaw'

addon-config-token:
    docker exec addon-test bash -lc 'openclaw config get gateway.auth.token'

addon-config-show:
    docker exec addon-test python3 -c 'from pathlib import Path; print(Path("/config/.openclaw/openclaw.json").read_text())'

openclaw-install:
    cd ../openclaw && pnpm install

openclaw-test:
    cd ../openclaw && pnpm test

openclaw-test-provider-timeout:
    cd ../openclaw && pnpm test test/provider-timeout.e2e.test.ts

git-status-ha:
    git status --short

git-diff-addon:
    git diff main..HEAD -- openclaw_assistant

git-status-openclaw:
    cd ../openclaw && git status --short

git-show-test-config:
    git show HEAD:test_config/.openclaw/openclaw.json

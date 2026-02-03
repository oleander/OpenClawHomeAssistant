# syntax=docker/dockerfile:1.7
ARG BUILD_FROM
FROM ${BUILD_FROM}

# Use BuildKit cache mounts for faster rebuilds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    bash git openssh-client ca-certificates tzdata jq curl \
    tar xz-utils file python3 nginx gnupg build-essential sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 (OpenClaw requires 20+)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install ttyd
ARG TARGETARCH
RUN ARCH=$(echo ${TARGETARCH:-$(dpkg --print-architecture)} | sed 's|arm64|aarch64|;s|arm/v7|armhf|;s|armv7|armhf|;s|amd64|x86_64|') \
    && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${ARCH}" -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd

# Homebrew setup - SLOWEST PART: cache this layer aggressively
ENV HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_INSTALL_CLEANUP=1 \
    HOMEBREW_NO_ENV_HINTS=1 \
    HOMEBREW_NO_ANALYTICS=1 \
    PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

RUN useradd -m -s /bin/bash linuxbrew \
    && usermod -aG sudo linuxbrew \
    && mkdir -p /home/linuxbrew/.linuxbrew \
    && chown -R linuxbrew: /home/linuxbrew/.linuxbrew

USER linuxbrew
RUN --mount=type=cache,target=/home/linuxbrew/.cache,uid=1000,gid=1000 \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    && brew install gcc

USER root

# Install OpenClaw - pin version for cache stability
RUN --mount=type=cache,target=/root/.npm \
    npm config set fund false && npm config set audit false \
    && npm install -g openclaw@2026.1.30

# Copy application files
COPY --chmod=755 entrypoint.sh /
COPY --chmod=755 oc_config_helper.py /
COPY nginx.conf.tpl landing.html.tpl /etc/nginx/

RUN mkdir -p /run/nginx

CMD ["/entrypoint.sh"]

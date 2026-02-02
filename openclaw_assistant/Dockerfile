ARG BUILD_FROM
FROM ${BUILD_FROM}

# Base image is Debian Bookworm (glibc). This avoids musl-related native module issues
# that occur on Alpine (e.g. clipboard, node-llama-cpp).

# Install base packages (without nodejs/npm - we'll get Node 22 from NodeSource)
# Includes build-essential and vim as recommended by Homebrew
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    git \
    openssh-client \
    ca-certificates \
    tzdata \
    jq \
    curl \
    tar \
    xz-utils \
    file \
    procps \
    sudo \
    python3 \
    nginx \
    gnupg \
    build-essential \
    vim \
    procps \
    sudo \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS from NodeSource (Debian Bookworm ships Node 18, but OpenClaw requires 20+)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y nodejs \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Install Homebrew (Linuxbrew) in the default Linux prefix
# Brew is the default package manager for OpenClaw
# https://docs.openclaw.ai/platforms/mac/skills#install-actions
ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
ENV HOMEBREW_CELLAR=${HOMEBREW_PREFIX}/Cellar \
    HOMEBREW_REPOSITORY=${HOMEBREW_PREFIX}/Homebrew \
    PATH=${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:${PATH} \
    HOMEBREW_NO_ANALYTICS=1 \
    HOMEBREW_NO_AUTO_UPDATE=1

RUN useradd -m -s /bin/bash linuxbrew \
 && echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
 && mkdir -p "$HOMEBREW_PREFIX" \
 && chown -R linuxbrew:linuxbrew /home/linuxbrew

USER linuxbrew
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
RUN brew install gcc # Recommended by Homebrew

USER root
RUN printf 'eval "$(%s/bin/brew shellenv)"\n' "$HOMEBREW_PREFIX" \
 | tee /etc/profile.d/brew.sh \
 | tee -a /etc/bash.bashrc > /dev/null

VOLUME ["/home/linuxbrew/.linuxbrew"]

# Install ttyd (web terminal) - not in Debian repos, download binary
# Docker TARGETARCH: amd64, arm64, arm/v7 → ttyd filenames: x86_64, aarch64, armhf
ARG TARGETARCH
RUN ARCH=$(echo ${TARGETARCH:-$(dpkg --print-architecture)} | sed 's|arm64|aarch64|;s|arm/v7|armhf|;s|armv7|armhf|;s|amd64|x86_64|') \
 && echo "Downloading ttyd for arch: ${ARCH}" \
 && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${ARCH}" -o /usr/local/bin/ttyd \
 && chmod +x /usr/local/bin/ttyd

RUN node -v && npm -v

# Install OpenClaw globally
RUN npm config set fund false && npm config set audit false \
 && npm install -g openclaw@2026.1.30

COPY run.sh /run.sh
COPY oc_config_helper.py /oc_config_helper.py
COPY nginx.conf.tpl /etc/nginx/nginx.conf.tpl
COPY landing.html.tpl /etc/nginx/landing.html.tpl
RUN chmod +x /run.sh /oc_config_helper.py \
 && mkdir -p /run/nginx

CMD [ "/run.sh" ]

# syntax=docker/dockerfile:1
# =============================================================================
# code-server Dockerfile
# =============================================================================
# Builds a customized code-server image on top of the official Coder image.
# Adds system-level tools: git, Node.js (LTS), PHP 8, Composer.
#
# To update code-server, change CODE_SERVER_VERSION in .env and rebuild:
#   docker compose up -d --build
#
# Extensions are NOT pre-baked here. They are installed by entrypoint.sh on
# first container start into the persistent volume, so they survive rebuilds.
# =============================================================================

ARG CODE_SERVER_VERSION=4.102.1

# ---------------------------------------------------------------------------
# Base image — official GitHub Container Registry (multi-arch: amd64 + arm64)
# ---------------------------------------------------------------------------
FROM ghcr.io/coder/code-server:${CODE_SERVER_VERSION}

ARG CODE_SERVER_VERSION
LABEL maintainer="homelab"
LABEL org.opencontainers.image.title="code-server homelab"
LABEL org.opencontainers.image.source="https://github.com/coder/code-server"
LABEL org.opencontainers.image.version="${CODE_SERVER_VERSION}"

# ---------------------------------------------------------------------------
# Install system packages (as root)
# ---------------------------------------------------------------------------
USER root

# 1. Base utilities + PHP
RUN apt-get update && apt-get install -y --no-install-recommends \
        # Version control
        git \
        git-lfs \
        # Networking & debugging
        curl \
        wget \
        jq \
        # PHP 8 (adjust version as needed)
        php \
        php-cli \
        php-curl \
        php-mbstring \
        php-xml \
        php-zip \
        # Misc
        procps \
        unzip \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. Node.js LTS via NodeSource (clean, official, no version manager needed)
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    # Install common global package managers
    && npm install -g yarn pnpm

# 3. Composer (PHP dependency manager)
RUN curl -sS https://getcomposer.org/installer \
        | php -- --install-dir=/usr/local/bin --filename=composer \
    && composer --version

# ---------------------------------------------------------------------------
# Stage default VS Code settings for the entrypoint to pick up
# ---------------------------------------------------------------------------
RUN mkdir -p /etc/code-server
COPY config/settings.json /etc/code-server/default-settings.json

# ---------------------------------------------------------------------------
# Copy and register the entrypoint script
# ---------------------------------------------------------------------------
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ---------------------------------------------------------------------------
# Drop back to the unprivileged `coder` user (UID 1000, provided by base image)
# ---------------------------------------------------------------------------
USER coder

# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------
EXPOSE 8080
WORKDIR /home/coder

# Override the base image's entrypoint with our bootstrap script.
# The script finishes with `exec code-server …` so signals are passed correctly.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

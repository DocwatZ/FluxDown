# syntax=docker/dockerfile:1
# FluxDown headless server image: Web SPA (web/) + fluxdown-server (native/server).
# Multi-arch: linux/amd64 + linux/arm64. The compile stages run on the build
# host's native architecture (--platform=$BUILDPLATFORM) and cross-compile for
# TARGETARCH, avoiding slow QEMU-emulated Rust builds.
#
# Build (context = repository root, relies on root .dockerignore):
#   docker build -f docker/server.Dockerfile -t fluxdown-server .
#   docker buildx build --platform linux/amd64,linux/arm64 -f docker/server.Dockerfile .
# Inject version at build time (/ping, /api/v1/stats, OpenAPI display):
#   docker build -f docker/server.Dockerfile --build-arg FLUXDOWN_SERVER_VERSION=1.2.3 .
#
# Run (management token printed to stderr on first start — save it!):
#   docker run -d -p 17800:17800 -v fluxdown-data:/data fluxdown-server
#
# Unraid / NAS PUID/PGID usage (avoids permission issues on host-mounted volumes):
#   docker run -d -e PUID=1000 -e PGID=1000 \
#     -p 17800:17800 \
#     -v /mnt/user/appdata/fluxdown:/data \
#     -v /mnt/user/Downloads:/downloads \
#     -e FLUXDOWN_DOWNLOAD_DIR=/downloads \
#     fluxdown-server

# ── Stage 1: Web frontend (Vite SPA, bun lockfile; output is arch-independent) ──
FROM --platform=$BUILDPLATFORM oven/bun:1 AS web
WORKDIR /src/web
COPY web/package.json web/bun.lock ./
RUN bun install --frozen-lockfile
COPY web/ ./
RUN bun run build

# ── Stage 2: Rust server (workspace member, cross-compiled for TARGETARCH) ──
# Full rustls (no openssl), SQLite bundled by sqlx (cc cross-toolchain), no extra
# system dependencies at runtime.
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS server
ARG TARGETARCH
WORKDIR /src
# aarch64 cross-linker / cc (needed by libsqlite3-sys and other build scripts)
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
    AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar
RUN case "$TARGETARCH" in \
      amd64) echo x86_64-unknown-linux-gnu > /rust-target ;; \
      arm64) echo aarch64-unknown-linux-gnu > /rust-target \
        && rustup target add aarch64-unknown-linux-gnu \
        && apt-get update \
        && apt-get install -y --no-install-recommends gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
        && rm -rf /var/lib/apt/lists/* ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac
COPY Cargo.toml Cargo.lock ./
COPY native/ native/
# Build-time version injection (empty = not injected, binary falls back to crate version)
ARG FLUXDOWN_SERVER_VERSION
ENV FLUXDOWN_SERVER_VERSION=$FLUXDOWN_SERVER_VERSION
# cache mounts: incremental builds locally; registry cache avoids re-downloading crates
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --release --locked -p fluxdown_server --target "$(cat /rust-target)" \
    && cp "target/$(cat /rust-target)/release/fluxdown-server" /usr/local/bin/fluxdown-server

# ── Stage 3: Runtime (target-arch debian-slim + ca-certificates for rustls) ──
FROM debian:bookworm-slim
# gosu: privilege-drop helper used by the entrypoint to run as PUID/PGID
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gosu \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root service account (default when PUID/PGID are not set)
RUN groupadd -r -g 1000 fluxdown \
    && useradd -r -u 1000 -g fluxdown -d /data -s /sbin/nologin fluxdown

WORKDIR /app
COPY --from=server /usr/local/bin/fluxdown-server /app/fluxdown-server
COPY --from=web /src/web/dist /app/web

# Entrypoint: honour PUID/PGID for host-volume permission mapping (Unraid / NAS).
# If PUID or PGID are set, the uid/gid of the 'fluxdown' account is updated at
# container start and the server is exec'd as that user via gosu.
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment variables (see native/server/src/config.rs for full documentation):
#   FLUXDOWN_BIND           – listen address           (default: 0.0.0.0:17800)
#   FLUXDOWN_DATA_DIR       – DB + log directory       (default: /data)
#   FLUXDOWN_WEBROOT        – SPA static assets        (default: /app/web)
#   FLUXDOWN_LANG           – default UI language      (en / zh; unset = browser locale)
#   FLUXDOWN_DATABASE_URL   – external DB URL          (sqlite: or postgres:; unset = /data/*.db)
#   FLUXDOWN_DEMO           – demo mode flag           (1/true/yes to enable)
#   FLUXDOWN_DOWNLOAD_DIR   – download save directory  (written to config on first run)
#   PUID                    – UID to run the server as (default: 1000)
#   PGID                    – GID to run the server as (default: 1000)
ENV FLUXDOWN_BIND=0.0.0.0:17800 \
    FLUXDOWN_WEBROOT=/app/web \
    FLUXDOWN_DATA_DIR=/data \
    PUID=1000 \
    PGID=1000

VOLUME /data
EXPOSE 17800
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
    CMD curl -fsS "http://127.0.0.1:${FLUXDOWN_BIND##*:}/ping" || exit 1

ENTRYPOINT ["/entrypoint.sh"]

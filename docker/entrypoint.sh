#!/bin/sh
# FluxDown Server entrypoint — handles PUID/PGID remapping for Unraid / NAS deployments.
#
# When PUID and/or PGID are set to values other than the default (1000), the
# 'fluxdown' service account is updated to match before the server process is
# exec'd under that identity.  This ensures files written to host-mounted volumes
# (e.g. /data, /downloads) are owned by the expected host user, avoiding common
# permission problems on Unraid and other NAS systems.
#
# Environment variables:
#   PUID  – UID to run the server as (default: 1000)
#   PGID  – GID to run the server as (default: 1000)
#   All other FLUXDOWN_* vars are passed through to the server binary unchanged.
set -e

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

echo "FluxDown Server starting (PUID=${PUID}, PGID=${PGID})"

# Apply group/user remapping only when values differ from defaults, or when the
# account does not already match (safe to call even on repeated restarts).
if [ "$(id -g fluxdown)" != "${PGID}" ]; then
    groupmod -o -g "${PGID}" fluxdown
fi
if [ "$(id -u fluxdown)" != "${PUID}" ]; then
    usermod -o -u "${PUID}" fluxdown
fi

# Ensure the data directory is owned by the service account so SQLite and log
# files can be created on first run.
mkdir -p "${FLUXDOWN_DATA_DIR:-/data}"
chown -R fluxdown:fluxdown "${FLUXDOWN_DATA_DIR:-/data}"

# If a custom download directory is specified, create and chown it too.
if [ -n "${FLUXDOWN_DOWNLOAD_DIR}" ]; then
    mkdir -p "${FLUXDOWN_DOWNLOAD_DIR}"
    chown fluxdown:fluxdown "${FLUXDOWN_DOWNLOAD_DIR}" 2>/dev/null || true
fi

# Drop privileges and exec the server (replaces this shell; PID 1 is the server).
exec gosu fluxdown /app/fluxdown-server "$@"

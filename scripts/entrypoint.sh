#!/usr/bin/env bash
# =============================================================================
# scripts/entrypoint.sh  —  code-server container startup script
# =============================================================================
# Responsibilities:
#   1. Ensure required directories exist in the mounted volume.
#   2. Copy default VS Code settings on first run (non-destructive).
#   3. Install VS Code extensions on first run.
#   4. Hand off execution to code-server with the correct CLI flags.
#
# This script runs as the `coder` user (UID 1000).
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
DATA_DIR="/home/coder/.local/share/code-server"
SETTINGS_FILE="${DATA_DIR}/User/settings.json"
EXTENSIONS_DIR="${DATA_DIR}/extensions"
SENTINEL="${DATA_DIR}/.extensions_initialized"
DEFAULT_SETTINGS_SRC="/etc/code-server/default-settings.json"

# ---------------------------------------------------------------------------
# 1. Ensure directories exist (volume may be empty on first run)
# ---------------------------------------------------------------------------
mkdir -p \
    "${DATA_DIR}/User" \
    "${EXTENSIONS_DIR}" \
    "${HOME}/projects"

# ---------------------------------------------------------------------------
# 2. Copy default settings on first run
#    We only copy if the user hasn't already created their own settings file.
# ---------------------------------------------------------------------------
if [ ! -f "${SETTINGS_FILE}" ] && [ -f "${DEFAULT_SETTINGS_SRC}" ]; then
    echo "[entrypoint] First run — copying default VS Code settings..."
    cp "${DEFAULT_SETTINGS_SRC}" "${SETTINGS_FILE}"
fi

# ---------------------------------------------------------------------------
# 3. Install extensions on first run
#    A sentinel file prevents reinstalling on every container start.
#    Add or remove extension IDs from the list below as needed.
# ---------------------------------------------------------------------------
if [ ! -f "${SENTINEL}" ]; then
    echo "[entrypoint] First run — installing VS Code extensions..."
    echo "[entrypoint] This may take a few minutes. Grab a coffee ☕"

    EXTENSIONS=(
        "github.copilot"
        "github.copilot-chat"
    )

    for ext in "${EXTENSIONS[@]}"; do
        echo "[entrypoint]   → ${ext}"
        code-server --install-extension "${ext}" \
            --extensions-dir "${EXTENSIONS_DIR}" \
            2>&1 | grep -v "^$" || \
            echo "[entrypoint]   WARNING: Could not install ${ext}. It can be installed manually from the Extensions panel."
    done

    touch "${SENTINEL}"
    echo "[entrypoint] Extension installation complete."
fi

# ---------------------------------------------------------------------------
# 4. Start code-server
#    --bind-addr     : listen on all interfaces inside the container on port 8080
#    --auth          : 'none' disables the login screen (Pangolin SSO handles auth)
#                      set AUTH=password in .env to re-enable the built-in prompt
#    --user-data-dir : point to the volume-backed data directory
#    --extensions-dir: use the persistent extensions directory
#    Last argument   : default folder to open in the editor
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting code-server..."

exec code-server \
    --bind-addr "0.0.0.0:8080" \
    --auth "${AUTH:-none}" \
    --user-data-dir "${DATA_DIR}" \
    --extensions-dir "${EXTENSIONS_DIR}" \
    "${DEFAULT_WORKSPACE:-/home/coder/projects}"

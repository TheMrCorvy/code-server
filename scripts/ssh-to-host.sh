#!/usr/bin/env bash
# =============================================================================
# scripts/ssh-to-host.sh  —  code-server default terminal shell
# =============================================================================
# Used as the default terminal profile in code-server (settings.json).
# Every new terminal tab runs this script, which SSHes into the real host
# machine and gives you a native shell with access to all host tools.
#
# Environment variables (set in .env, passed in via docker-compose.yml):
#   SSH_USER  — username on the host machine
#   SSH_HOST  — hostname the container uses to reach the host
#               (default: host.docker.internal)
#   SSH_PORT  — SSH port on the host (default: 22)
#
# Behaviour:
#   • On clean exit (user typed 'exit' / 'logout') → terminal ends normally.
#   • On unexpected disconnect                      → retries up to MAX_RETRIES.
#   • After MAX_RETRIES failures                    → drops to container bash.
# =============================================================================

SSH_USER="${SSH_USER:-}"
SSH_HOST="${SSH_HOST:-host.docker.internal}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="/home/coder/.ssh/id_ed25519"

MAX_RETRIES=5
RETRY_DELAY=3

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
clear
printf '\033[1;36m'
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  code-server  ›  Host Terminal"
printf "  \033[0;37m%s\033[1;36m@\033[0;37m%s\033[1;36m:\033[0;37m%s\n" "${SSH_USER}" "${SSH_HOST}" "${SSH_PORT}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf '\033[0m\n'

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [ ! -f "${SSH_KEY}" ]; then
    printf '\033[0;31m✗  SSH key not found: %s\033[0m\n\n' "${SSH_KEY}"
    echo "   To set up the SSH connection:"
    echo "   1. Follow docs/ssh-setup-guide.md"
    echo "   2. Place your private key at ./secrets/ssh_host_key"
    echo "   3. Restart the container:  docker compose restart code-server"
    echo ""
    echo "   Dropping to container shell. Run 'ssh-to-host' to retry after setup."
    exec /bin/bash
fi

if [ -z "${SSH_USER}" ]; then
    printf '\033[0;33m⚠  SSH_USER is not set in .env — connection may fail.\033[0m\n\n'
fi

# ---------------------------------------------------------------------------
# Connection loop
# ---------------------------------------------------------------------------
attempt=0

while true; do
    attempt=$((attempt + 1))

    ssh \
        -i "${SSH_KEY}" \
        -p "${SSH_PORT}" \
        -o "StrictHostKeyChecking=accept-new" \
        -o "ServerAliveInterval=30" \
        -o "ServerAliveCountMax=3" \
        -o "ConnectTimeout=10" \
        "${SSH_USER}@${SSH_HOST}"

    exit_code=$?

    # Clean exit — user typed 'exit' or 'logout'. Do not reconnect.
    if [ "${exit_code}" -eq 0 ]; then
        echo ""
        printf '\033[0;90mSession ended cleanly. Open a new terminal tab to reconnect.\033[0m\n'
        break
    fi

    # Unexpected disconnect — retry up to MAX_RETRIES.
    if [ "${attempt}" -lt "${MAX_RETRIES}" ]; then
        echo ""
        printf '\033[0;33m⚠  Disconnected (code %d). Reconnecting in %ds… [%d/%d]\033[0m\n' \
            "${exit_code}" "${RETRY_DELAY}" "${attempt}" "${MAX_RETRIES}"
        sleep "${RETRY_DELAY}"
    else
        echo ""
        printf '\033[0;31m✗  Could not reconnect after %d attempts.\033[0m\n' "${MAX_RETRIES}"
        echo "   Check that SSH is enabled on the host and try again."
        echo "   See docs/ssh-setup-guide.md for troubleshooting."
        echo ""
        echo "   Dropping to container shell. Run 'ssh-to-host' to retry."
        exec /bin/bash
    fi
done

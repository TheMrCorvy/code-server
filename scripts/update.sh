#!/usr/bin/env bash
# =============================================================================
# scripts/update.sh  —  Update code-server to a new version
# =============================================================================
# Usage (run from the repo root):
#   bash scripts/update.sh 4.200.0   # update to a specific version
#   bash scripts/update.sh latest    # fetch and apply the latest release (needs jq)
# =============================================================================

set -euo pipefail

# Always resolve paths relative to the repo root, not the scripts/ folder
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"

# --------------------------------------------------------------------------
# Resolve target version
# --------------------------------------------------------------------------
if [[ "${1:-}" == "latest" || -z "${1:-}" ]]; then
  if ! command -v jq &>/dev/null; then
    echo "❌  'jq' is required to resolve the latest version. Install it or pass a version explicitly."
    exit 1
  fi
  echo "🔍  Fetching latest code-server release from GitHub..."
  TARGET_VERSION="$(curl -fsSL https://api.github.com/repos/coder/code-server/releases/latest | jq -r '.tag_name' | sed 's/^v//')"
  echo "   Latest version: ${TARGET_VERSION}"
else
  TARGET_VERSION="${1}"
fi

# --------------------------------------------------------------------------
# Update .env file
# --------------------------------------------------------------------------
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "⚠️  .env file not found. Copying from .env.example..."
  cp "${REPO_DIR}/.env.example" "${ENV_FILE}"
fi

CURRENT_VERSION="$(grep -E '^CODE_SERVER_VERSION=' "${ENV_FILE}" | cut -d= -f2 | tr -d '"' | tr -d "'" || echo 'unknown')"
echo "📦  Current version : ${CURRENT_VERSION}"
echo "🚀  Target version  : ${TARGET_VERSION}"

if [[ "${CURRENT_VERSION}" == "${TARGET_VERSION}" ]]; then
  echo "✅  Already on version ${TARGET_VERSION}. Nothing to do."
  exit 0
fi

if sed -i.bak "s/^CODE_SERVER_VERSION=.*/CODE_SERVER_VERSION=${TARGET_VERSION}/" "${ENV_FILE}"; then
  rm -f "${ENV_FILE}.bak"
  echo "✅  Updated CODE_SERVER_VERSION in .env → ${TARGET_VERSION}"
else
  echo "❌  Failed to update .env. Please update CODE_SERVER_VERSION manually."
  exit 1
fi

# --------------------------------------------------------------------------
# Rebuild and restart
# --------------------------------------------------------------------------
echo ""
echo "🔨  Rebuilding Docker image for version ${TARGET_VERSION}..."
docker compose -f "${REPO_DIR}/docker-compose.yml" build \
  --no-cache \
  --build-arg "CODE_SERVER_VERSION=${TARGET_VERSION}"

echo ""
echo "♻️  Restarting code-server container..."
docker compose -f "${REPO_DIR}/docker-compose.yml" up -d --force-recreate

echo ""
echo "✅  code-server updated to ${TARGET_VERSION} and restarted."
echo "   Access it at: http://localhost:8080"

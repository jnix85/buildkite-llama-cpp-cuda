#!/usr/bin/env bash
# ==============================================================================
# llama.cpp Automated Release Tracker & BuildKit Updater
# Target: Sigrun (Overclocked i9-9900K 8C | RTX 2070 Super CC 7.5 | Ubuntu 26.04)
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_DIR}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking for upstream llama.cpp releases..."

# 1. Fetch latest release tag (GitHub API with git ls-remote fallback)
LATEST_TAG=""
if command -v curl &>/dev/null && command -v jq &>/dev/null; then
    LATEST_TAG=$(curl -sL https://api.github.com/repos/ggerganov/llama.cpp/releases/latest | jq -r '.tag_name // empty' 2>/dev/null || true)
fi

if [ -z "${LATEST_TAG}" ]; then
    echo "GitHub API unavailable or rate-limited, checking via git ls-remote..."
    LATEST_TAG=$(git ls-remote --tags --sort='v:refname' https://github.com/ggerganov/llama.cpp.git | tail -n1 | awk -F'/' '{print $NF}')
fi

if [ -z "${LATEST_TAG}" ]; then
    echo "ERROR: Could not retrieve latest release tag from llama.cpp repository."
    exit 1
fi

CLEAN_TAG="$(echo "${LATEST_TAG}" | tr -d 'v')"
echo "Latest upstream release: ${LATEST_TAG} (Normalized: ${CLEAN_TAG})"

# 2. Check currently installed package version
INSTALLED_VER="$(dpkg-query -W -f='${Version}' llama-server-cuda 2>/dev/null || echo 'none')"
echo "Currently installed package version: ${INSTALLED_VER}"

if [ "${INSTALLED_VER}" = "${CLEAN_TAG}" ]; then
    echo "llama-server-cuda is up to date (${INSTALLED_VER}). No action needed."
    exit 0
fi

echo "==================================================================="
echo " Update detected: Upgrading llama-server-cuda to ${LATEST_TAG}..."
echo "==================================================================="

# 3. Build & Package via BuildKit
mkdir -p dist
echo "==> Running BuildKit build for tag ${LATEST_TAG}..."
LLAMA_TAG="${LATEST_TAG}" docker buildx bake deb

DEB_FILE="dist/llama-server-cuda_${CLEAN_TAG}_amd64.deb"
if [ ! -f "${DEB_FILE}" ]; then
    DEB_FILE=$(ls -t dist/llama-server-cuda_*_amd64.deb 2>/dev/null | head -n1 || true)
fi

if [ -z "${DEB_FILE}" ] || [ ! -f "${DEB_FILE}" ]; then
    echo "ERROR: BuildKit completed but expected .deb package was not generated!"
    exit 1
fi

echo "==> Successfully generated package: ${DEB_FILE}"

# 4. Install updated package
echo "==> Installing updated package via apt..."
sudo apt install -y "./${DEB_FILE}"

# 5. Restart llama-server service if running
if systemctl is-active --quiet llama-server 2>/dev/null; then
    echo "==> Restarting llama-server.service..."
    sudo systemctl restart llama-server
    echo "==> llama-server restarted successfully."
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Update to ${LATEST_TAG} completed successfully."

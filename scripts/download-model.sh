#!/usr/bin/env bash
# ==============================================================================
# Helper to download Qwen3.8-27B-Uncensored Q4_K_M GGUF model into /models/
# ==============================================================================
set -euo pipefail

MODEL_DIR="/models"
MODEL_FILE="Qwen3.8-27B-Uncensored-Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/JonathanColetti/Qwen3.8-27B-Uncensored-GGUF/resolve/main/${MODEL_FILE}"
TARGET="${MODEL_DIR}/${MODEL_FILE}"

if [ ! -d "${MODEL_DIR}" ]; then
    echo "Creating ${MODEL_DIR}..."
    sudo mkdir -p "${MODEL_DIR}"
    sudo chown -R "$(id -un):$(id -gn)" "${MODEL_DIR}"
    sudo chmod 775 "${MODEL_DIR}"
fi

if [ -f "${TARGET}" ]; then
    echo "Model already exists at: ${TARGET}"
    ls -lh "${TARGET}"
    exit 0
fi

echo "==> Downloading ${MODEL_FILE} (~16.8 GB) from Hugging Face..."
echo "    Source: ${MODEL_URL}"
echo "    Target: ${TARGET}"
curl -L --progress-bar -C - "${MODEL_URL}" -o "${TARGET}.tmp"
mv "${TARGET}.tmp" "${TARGET}"

echo "==> Download complete: ${TARGET}"
ls -lh "${TARGET}"

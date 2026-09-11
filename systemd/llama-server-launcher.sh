#!/usr/bin/env bash
# ==============================================================================
# llama-server Service Launcher
# Wrapper for systemd service invocation with pre-flight configuration validation
# Target: Sigrun (i9-9900K 8C | 64GB RAM | RTX 2070 Super 8GB VRAM CC 7.5 | NVMe)
# ==============================================================================
set -euo pipefail

# Configuration passed via environment (/etc/default/llama-server)
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
MODEL_PATH="${MODEL_PATH:-}"
HF_REPO="${HF_REPO:-}"
HF_FILE="${HF_FILE:-}"
MODEL_ALIAS="${MODEL_ALIAS:-}"
CTX_SIZE="${CTX_SIZE:-8192}"
GPU_LAYERS="${GPU_LAYERS:-23}"
THREADS="${THREADS:-8}"
BATCH_SIZE="${BATCH_SIZE:-512}"
UBATCH_SIZE="${UBATCH_SIZE:-512}"
EXTRA_FLAGS="${EXTRA_FLAGS:-}"

# Ensure /models directory exists
if [ ! -d "/models" ]; then
    mkdir -p "/models" 2>/dev/null || true
fi

# Pre-flight check: Network port availability
if command -v ss >/dev/null 2>&1; then
    if ss -tulpn 2>/dev/null | grep -qE "(0\.0\.0\.0|::|127\.0\.0\.1):${PORT}\b"; then
        echo "========================================================================" >&2
        echo "ERROR: Port ${PORT} is already in use by another process!" >&2
        ss -tulpn 2>/dev/null | grep -E ":${PORT}\b" >&2 || true
        echo "Please adjust PORT in /etc/default/llama-server (e.g. PORT=8000 or 8081)." >&2
        echo "========================================================================" >&2
        exit 78  # EX_CONFIG: prevents systemd rapid crash-restart loop
    fi
fi

ARGS=()

# Determine model source: Local file vs HuggingFace repository
if [ -n "${MODEL_PATH}" ] && [ -f "${MODEL_PATH}" ]; then
    ARGS+=("-m" "${MODEL_PATH}")
elif [ -n "${HF_REPO}" ]; then
    if [ -n "${MODEL_PATH}" ] && [ ! -f "${MODEL_PATH}" ]; then
        echo "Notice: Local model '${MODEL_PATH}' not found."
        echo "Notice: Falling back to Hugging Face repository: ${HF_REPO}"
    fi
    ARGS+=("-hf" "${HF_REPO}")
    if [ -n "${HF_FILE}" ]; then
        ARGS+=("-hff" "${HF_FILE}")
    fi
else
    echo "========================================================================" >&2
    echo "ERROR: Model not found and no Hugging Face fallback configured!" >&2
    if [ -n "${MODEL_PATH}" ]; then
        echo "Specified MODEL_PATH does not exist: ${MODEL_PATH}" >&2
        echo "Please place your GGUF model in /models/ or adjust MODEL_PATH." >&2
    else
        echo "Neither MODEL_PATH nor HF_REPO is defined in /etc/default/llama-server." >&2
    fi
    echo "Edit /etc/default/llama-server to configure your model." >&2
    echo "========================================================================" >&2
    exit 78  # EX_CONFIG: prevents systemd rapid crash-restart loop
fi

# Model alias
if [ -n "${MODEL_ALIAS}" ]; then
    ARGS+=("--alias" "${MODEL_ALIAS}")
fi

# Core hardware / network arguments
ARGS+=(
    "--host" "${HOST}"
    "--port" "${PORT}"
    "-c" "${CTX_SIZE}"
    "-ngl" "${GPU_LAYERS}"
    "-t" "${THREADS}"
    "-b" "${BATCH_SIZE}"
    "-ub" "${UBATCH_SIZE}"
)

# Append extra hardware optimization flags
if [ -n "${EXTRA_FLAGS}" ]; then
    read -r -a EXTRA_ARR <<< "${EXTRA_FLAGS}"
    ARGS+=("${EXTRA_ARR[@]}")
fi

LLAMA_BIN="/usr/local/bin/llama-server"
if [ ! -x "${LLAMA_BIN}" ]; then
    LLAMA_BIN="/opt/llama.cpp/llama-server"
fi

echo "==> Launching llama-server on ${HOST}:${PORT}..."
exec "${LLAMA_BIN}" "${ARGS[@]}"

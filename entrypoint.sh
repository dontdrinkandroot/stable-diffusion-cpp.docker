#!/bin/bash
set -e

MODEL_DIR="${MODEL_DIR:-/models}"
LORA_DIR="${LORA_DIR:-/loras}"
PORT="${PORT:-1234}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"

if [ -z "$DIFFUSION_MODEL_URL" ] && [ -z "$VAE_URL" ] && [ -z "$LLM_URL" ]; then
    echo "ERROR: No model URLs configured."
    echo "Set at least one of DIFFUSION_MODEL_URL, VAE_URL, or LLM_URL."
    echo "Example:"
    echo "  DIFFUSION_MODEL_URL=https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF/resolve/main/flux-2-klein-9b-Q6_K.gguf"
    echo "  VAE_URL=https://huggingface.co/black-forest-labs/FLUX.2-dev/resolve/main/ae.safetensors"
    echo "  LLM_URL=https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q6_K.gguf"
    exit 1
fi

if [ -n "$HF_TOKEN" ]; then
    AUTH_HEADER="--header=\"Authorization: Bearer $HF_TOKEN\""
else
    AUTH_HEADER=""
    echo "WARNING: HF_TOKEN is not set. Downloads from gated repos will fail."
fi

INPUT_FILE="/tmp/aria2-input.txt"
> "$INPUT_FILE"

if [ -n "$DIFFUSION_MODEL_URL" ]; then
    echo "${DIFFUSION_MODEL_URL}" >> "$INPUT_FILE"
    echo "  out=$(basename "$DIFFUSION_MODEL_URL")" >> "$INPUT_FILE"
fi

if [ -n "$VAE_URL" ]; then
    echo "${VAE_URL}" >> "$INPUT_FILE"
    echo "  out=$(basename "$VAE_URL")" >> "$INPUT_FILE"
fi

if [ -n "$LLM_URL" ]; then
    echo "${LLM_URL}" >> "$INPUT_FILE"
    echo "  out=$(basename "$LLM_URL")" >> "$INPUT_FILE"
fi

attempt=1
until [ $attempt -gt "$MAX_ATTEMPTS" ]; do
    echo "=== Downloading models (attempt $attempt/$MAX_ATTEMPTS) ==="
    if aria2c \
        -c \
        -x16 \
        -s16 \
        -j3 \
        -k 1M \
        ${AUTH_HEADER} \
        -d "$MODEL_DIR" \
        -i "$INPUT_FILE"; then
        echo "=== Download complete ==="
        break
    else
        echo "=== Download attempt $attempt failed ==="
        attempt=$((attempt + 1))
        if [ $attempt -gt "$MAX_ATTEMPTS" ]; then
            echo "ERROR: Download failed after $MAX_ATTEMPTS attempts."
            rm -f "$INPUT_FILE"
            exit 1
        fi
    fi
done

rm -f "$INPUT_FILE"

mkdir -p "$LORA_DIR"

echo "=== Starting sd-server ==="

cd "$MODEL_DIR"

DIFFUSION_MODEL_FLAG=""
if [ -n "$DIFFUSION_MODEL_URL" ]; then
    DIFFUSION_MODEL_FLAG="--diffusion-model $MODEL_DIR/$(basename "$DIFFUSION_MODEL_URL")"
fi

VAE_FLAG=""
if [ -n "$VAE_URL" ]; then
    VAE_FLAG="--vae $MODEL_DIR/$(basename "$VAE_URL")"
fi

LLM_FLAG=""
if [ -n "$LLM_URL" ]; then
    LLM_FLAG="--llm $MODEL_DIR/$(basename "$LLM_URL")"
fi

exec /sd-server \
    $DIFFUSION_MODEL_FLAG \
    $VAE_FLAG \
    $LLM_FLAG \
    --listen-ip 0.0.0.0 \
    --listen-port "$PORT" \
    --diffusion-fa \
    --offload-to-cpu \
    --lora-model-dir "$LORA_DIR" \
    "$@"

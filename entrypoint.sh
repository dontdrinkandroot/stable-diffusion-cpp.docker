#!/bin/bash
set -e

MODEL_DIR="${MODEL_DIR:-/models}"
PORT="${PORT:-1234}"
RCLONE_STREAMS="${RCLONE_STREAMS:-4}"

DIFFUSION_MODEL="$MODEL_DIR/flux-2-klein-9b-Q6_K.gguf"
VAE="$MODEL_DIR/ae.safetensors"
LLM="$MODEL_DIR/Qwen3-8B-Q6_K.gguf"

RCLONE_OPTS=(
    --multi-thread-streams "$RCLONE_STREAMS"
    --retries 5
    --low-level-retries 10
    --no-clobber
    --transfers 3
    -P
)

if [ -n "$HF_TOKEN" ]; then
    RCLONE_OPTS+=(--header-download "Authorization: Bearer $HF_TOKEN")
fi

echo "=== Downloading models ==="

URLS_CSV="/tmp/urls.csv"
: > "$URLS_CSV"

if [ ! -f "$DIFFUSION_MODEL" ]; then
    echo "https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF/resolve/main/flux-2-klein-9b-Q6_K.gguf,flux-2-klein-9b-Q6_K.gguf" >> "$URLS_CSV"
else
    echo "Already exists: $DIFFUSION_MODEL"
fi

if [ ! -f "$VAE" ]; then
    if [ -z "$HF_TOKEN" ]; then
        echo "ERROR: $VAE not found. black-forest-labs/FLUX.2-dev is a gated repo."
        echo "Please set HF_TOKEN after accepting the license at:"
        echo "  https://huggingface.co/black-forest-labs/FLUX.2-dev"
        exit 1
    fi
    echo "https://huggingface.co/black-forest-labs/FLUX.2-dev/resolve/main/ae.safetensors,ae.safetensors" >> "$URLS_CSV"
else
    echo "Already exists: $VAE"
fi

if [ ! -f "$LLM" ]; then
    echo "https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q6_K.gguf,Qwen3-8B-Q6_K.gguf" >> "$URLS_CSV"
else
    echo "Already exists: $LLM"
fi

if [ -s "$URLS_CSV" ]; then
    rclone copyurl "${RCLONE_OPTS[@]}" --urls "$URLS_CSV" "$MODEL_DIR"
fi

rm -f "$URLS_CSV"

echo "=== Starting sd-server ==="

exec /sd-server \
    --diffusion-model "$DIFFUSION_MODEL" \
    --vae "$VAE" \
    --llm "$LLM" \
    --port "$PORT" \
    --diffusion-fa \
    --offload-to-cpu \
    "$@"

#!/bin/bash
set -e

MODEL_DIR="${MODEL_DIR:-/models}"
PORT="${PORT:-1234}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"

if [ -z "$HF_TOKEN" ]; then
    echo "ERROR: HF_TOKEN is required."
    echo "Please set HF_TOKEN after accepting the licenses at:"
    echo "  https://huggingface.co/black-forest-labs/FLUX.2-dev"
    exit 1
fi

DIFFUSION_MODEL="$MODEL_DIR/flux-2-klein-9b-Q6_K.gguf"
VAE="$MODEL_DIR/ae.safetensors"
LLM="$MODEL_DIR/Qwen3-8B-Q6_K.gguf"

INPUT_FILE="/tmp/aria2-input.txt"
cat > "$INPUT_FILE" <<EOF
https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF/resolve/main/flux-2-klein-9b-Q6_K.gguf
  out=flux-2-klein-9b-Q6_K.gguf
https://huggingface.co/black-forest-labs/FLUX.2-dev/resolve/main/ae.safetensors
  out=ae.safetensors
https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q6_K.gguf
  out=Qwen3-8B-Q6_K.gguf
EOF

attempt=1
until [ $attempt -gt "$MAX_ATTEMPTS" ]; do
    echo "=== Downloading models (attempt $attempt/$MAX_ATTEMPTS) ==="
    if aria2c \
        -c \
        -x16 \
        -s16 \
        -j3 \
        -k 1M \
        --header="Authorization: Bearer $HF_TOKEN" \
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

echo "=== Starting sd-server ==="

exec /sd-server \
    --diffusion-model "$DIFFUSION_MODEL" \
    --vae "$VAE" \
    --llm "$LLM" \
    --port "$PORT" \
    --diffusion-fa \
    --offload-to-cpu \
    "$@"

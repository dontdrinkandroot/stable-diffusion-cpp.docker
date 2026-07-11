#!/bin/bash
set -e

MODEL_DIR="${MODEL_DIR:-/models}"
LORA_DIR="${LORA_DIR:-/loras}"
PORT="${PORT:-1234}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"

if [ -z "$HF_TOKEN" ]; then
    echo "WARNING: HF_TOKEN is not set. Downloads from gated repos will fail."
    echo "Set HF_TOKEN after accepting the licenses at:"
    echo "  https://huggingface.co/black-forest-labs/FLUX.2-dev"
fi

DIFFUSION_MODEL_URL="${DIFFUSION_MODEL_URL:-https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF/resolve/main/flux-2-klein-9b-Q6_K.gguf}"
VAE_URL="${VAE_URL:-https://huggingface.co/black-forest-labs/FLUX.2-dev/resolve/main/ae.safetensors}"
LLM_URL="${LLM_URL:-https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q6_K.gguf}"

DIFFUSION_MODEL="$MODEL_DIR/$(basename "$DIFFUSION_MODEL_URL")"
VAE="$MODEL_DIR/$(basename "$VAE_URL")"
LLM="$MODEL_DIR/$(basename "$LLM_URL")"

INPUT_FILE="/tmp/aria2-input.txt"
cat > "$INPUT_FILE" <<EOF
${DIFFUSION_MODEL_URL}
  out=$(basename "$DIFFUSION_MODEL_URL")
${VAE_URL}
  out=$(basename "$VAE_URL")
${LLM_URL}
  out=$(basename "$LLM_URL")
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

mkdir -p "$LORA_DIR"

echo "=== Starting sd-server ==="

cd "$MODEL_DIR"

exec /sd-server \
    --diffusion-model "$DIFFUSION_MODEL" \
    --vae "$VAE" \
    --llm "$LLM" \
    --cfg-scale 1.0 \
    --steps 4 \
    --listen-ip 0.0.0.0 \
    --listen-port "$PORT" \
    --diffusion-fa \
    --offload-to-cpu \
    --lora-model-dir "$LORA_DIR" \
    --disable-auto-resize-ref-image \
    "$@"

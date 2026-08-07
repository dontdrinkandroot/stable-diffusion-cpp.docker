#!/bin/bash
set -e

MODEL_DIR="${MODEL_DIR:-/models}"
LORA_DIR="${LORA_DIR:-/loras}"
PORT="${PORT:-1234}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"

if [ -z "$DIFFUSION_MODEL_URL" ] && [ -z "$VAE_URL" ] && [ -z "$AUDIO_VAE_URL" ] && [ -z "$LLM_URL" ]; then
    echo "ERROR: No model URLs configured."
    echo "Set at least one of DIFFUSION_MODEL_URL, VAE_URL, AUDIO_VAE_URL, or LLM_URL."
    echo "Example:"
    echo "  DIFFUSION_MODEL_URL=https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF/resolve/main/flux-2-klein-9b-Q6_K.gguf"
    echo "  VAE_URL=https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"
    echo "  AUDIO_VAE_URL=https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors"
    echo "  LLM_URL=https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q6_K.gguf"
    exit 1
fi

AUTH_HEADERS=()
if [ -n "$HF_TOKEN" ]; then
    AUTH_HEADERS=(--header "Authorization: Bearer $HF_TOKEN")
else
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

if [ -n "$AUDIO_VAE_URL" ]; then
    echo "${AUDIO_VAE_URL}" >> "$INPUT_FILE"
    echo "  out=$(basename "$AUDIO_VAE_URL")" >> "$INPUT_FILE"
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
        "${AUTH_HEADERS[@]}" \
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

AUDIO_VAE_FLAG=""
if [ -n "$AUDIO_VAE_URL" ]; then
    AUDIO_VAE_FLAG="--audio-vae $MODEL_DIR/$(basename "$AUDIO_VAE_URL")"
fi

LLM_FLAG=""
if [ -n "$LLM_URL" ]; then
    LLM_FLAG="--llm $MODEL_DIR/$(basename "$LLM_URL")"
fi

DIFFUSION_FA_FLAG=""
if [ "${DIFFUSION_FA}" = "1" ]; then
    DIFFUSION_FA_FLAG="--diffusion-fa"
fi

OFFLOAD_TO_CPU_FLAG=""
if [ "${OFFLOAD_TO_CPU}" = "1" ]; then
    OFFLOAD_TO_CPU_FLAG="--offload-to-cpu"
fi

CFG_SCALE_FLAG=""
if [ -n "$CFG_SCALE" ]; then
    CFG_SCALE_FLAG="--cfg-scale $CFG_SCALE"
fi

STEPS_FLAG=""
if [ -n "$STEPS" ]; then
    STEPS_FLAG="--steps $STEPS"
fi

DISABLE_AUTO_RESIZE_REF_IMAGE_FLAG=""
if [ "${DISABLE_AUTO_RESIZE_REF_IMAGE}" = "1" ]; then
    DISABLE_AUTO_RESIZE_REF_IMAGE_FLAG="--disable-auto-resize-ref-image"
fi

SAMPLING_METHOD_FLAG=""
if [ -n "$SAMPLING_METHOD" ]; then
    SAMPLING_METHOD_FLAG="--sampling-method $SAMPLING_METHOD"
fi

SCHEDULER_FLAG=""
if [ -n "$SCHEDULER" ]; then
    SCHEDULER_FLAG="--scheduler $SCHEDULER"
fi

FLOW_SHIFT_FLAG=""
if [ -n "$FLOW_SHIFT" ]; then
    FLOW_SHIFT_FLAG="--flow-shift $FLOW_SHIFT"
fi

FPS_FLAG=""
if [ -n "$FPS" ]; then
    FPS_FLAG="--fps $FPS"
fi

VIDEO_FRAMES_FLAG=""
if [ -n "$VIDEO_FRAMES" ]; then
    VIDEO_FRAMES_FLAG="--video-frames $VIDEO_FRAMES"
fi

WIDTH_FLAG=""
if [ -n "$WIDTH" ]; then
    WIDTH_FLAG="--width $WIDTH"
fi

HEIGHT_FLAG=""
if [ -n "$HEIGHT" ]; then
    HEIGHT_FLAG="--height $HEIGHT"
fi

MAX_VRAM_FLAG=""
if [ -n "$MAX_VRAM" ]; then
    MAX_VRAM_FLAG="--max-vram $MAX_VRAM"
fi

VERBOSE_FLAG=""
if [ "${VERBOSE}" = "1" ]; then
    VERBOSE_FLAG="-v"
fi

AUTO_FIT_FLAG=""
if [ "${AUTO_FIT}" = "1" ]; then
    AUTO_FIT_FLAG="--auto-fit"
fi

CMD=(
    /sd-server
    $DIFFUSION_MODEL_FLAG
    $VAE_FLAG
    $AUDIO_VAE_FLAG
    $LLM_FLAG
    --listen-ip 0.0.0.0
    --listen-port "$PORT"
    $DIFFUSION_FA_FLAG
    $OFFLOAD_TO_CPU_FLAG
    $CFG_SCALE_FLAG
    $STEPS_FLAG
    $DISABLE_AUTO_RESIZE_REF_IMAGE_FLAG
    $SAMPLING_METHOD_FLAG
    $SCHEDULER_FLAG
    $FLOW_SHIFT_FLAG
    $FPS_FLAG
    $VIDEO_FRAMES_FLAG
    $WIDTH_FLAG
    $HEIGHT_FLAG
    $MAX_VRAM_FLAG
    $VERBOSE_FLAG
    $AUTO_FIT_FLAG
    --lora-model-dir "$LORA_DIR"
    "$@"
)

echo "=== sd-server command ==="
printf '%q ' "${CMD[@]}"
echo
echo "========================="

exec "${CMD[@]}"

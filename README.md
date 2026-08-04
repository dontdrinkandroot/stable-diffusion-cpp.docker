# stable-diffusion-cpp.docker

Generic Docker image for running [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) (CUDA variant).
Models are downloaded automatically on first startup via aria2c and cached in a
named volume for subsequent runs.

## Requirements

- NVIDIA GPU + NVIDIA drivers
- Docker with GPU support (Docker 19.03+ with `--gpus` or Docker Compose `deploy.resources`)
- HuggingFace token (**required** if any model URL points to a gated repo)

## Configuration

### 1. Set model URLs

You **must** set the model URLs via environment variables. There are no built-in
defaults — configure at least one of `DIFFUSION_MODEL_URL`, `VAE_URL`,
`AUDIO_VAE_URL`, or `LLM_URL` for the models you want to use.

### 2. Set your HuggingFace token

If any of your model URLs point to a gated HuggingFace repository (e.g.
`black-forest-labs/FLUX.2-dev` for the VAE), you need a token with access:

1. Create a token at https://huggingface.co/settings/tokens
2. Accept the required license at the gated repository's page

Export it in your shell (or place it in a `.env` file next to
`docker-compose.yml`):

```bash
export HF_TOKEN=hf_your_token_here
```

Or create a `.env` file:

```env
HF_TOKEN=hf_your_token_here
```

Docker Compose reads `.env` automatically; the compose file references it via
`${HF_TOKEN:-}` (docker-compose.yml:10).

### 3. Build and start

```bash
docker compose up -d --build
```

The first start downloads model files into the `models` named volume.
Downloads use aria2c with parallel connections and resume support.

### 4. Use the server

Once running, the sd-server listens on port `1234`. See the
[stable-diffusion.cpp API docs](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/docker.md)
for endpoint usage.

### Subsequent starts

The `models` volume persists across `docker compose down` / `up`. The entrypoint
skips any file already present, so subsequent starts launch immediately without
re-downloading. Only `docker compose down -v` (which deletes the volume) forces
a fresh download.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HF_TOKEN` | (empty) | HuggingFace token; **required** for gated repos. Optional if all URLs point to public repos. |
| `MODEL_DIR` | `/models` | Directory for model files (mapped to a volume) |
| `LORA_DIR` | `/loras` | Directory for LoRA files (mapped to a volume) |
| `PORT` | `1234` | sd-server HTTP port |
| `MAX_ATTEMPTS` | `3` | Max download retry attempts before failing |
| `DIFFUSION_MODEL_URL` | *(none — must be set)* | URL for the diffusion model file |
| `VAE_URL` | *(none — must be set)* | URL for the VAE file |
| `AUDIO_VAE_URL` | *(none)* | URL for the audio VAE file (passed via `--audio-vae`; required for audio-generating video models like MiniMax-H3) |
| `LLM_URL` | *(none — must be set)* | URL for the text encoder / LLM file |
| `DIFFUSION_FA` | *(empty)* | Set to `1` to enable `--diffusion-fa` (Flash Attention for diffusion model) |
| `OFFLOAD_TO_CPU` | *(empty)* | Set to `1` to enable `--offload-to-cpu` (offload to CPU when VRAM is insufficient) |
| `CFG_SCALE` | *(empty)* | Sets `--cfg-scale` value (classifier-free guidance scale) |
| `STEPS` | *(empty)* | Sets `--steps` value (number of sampling steps) |
| `DISABLE_AUTO_RESIZE_REF_IMAGE` | *(empty)* | Set to `1` to enable `--disable-auto-resize-ref-image` |

Local filenames are derived from the URL via `basename` (e.g. `.../foo.gguf` → `$MODEL_DIR/foo.gguf`).

### Example: FLUX.2-klein-9B

```env
DIFFUSION_MODEL_URL=https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF/resolve/main/flux-2-klein-9b-Q6_K.gguf
VAE_URL=https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors
LLM_URL=https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q6_K.gguf
DIFFUSION_FA=1
STEPS=4
CFG_SCALE=1.0
```

### Example: MiniMax-H3 (FL2VA)

MiniMax-H3 jointly generates video and stereo audio. It requires four
components, wired via `--diffusion-model`, `--vae`, `--audio-vae`, and `--llm`:

```env
DIFFUSION_MODEL_URL=https://huggingface.co/leejet/MiniMax-H3-GGUF/resolve/main/minimax_h3_fl2va-Q4_K_M.gguf
VAE_URL=https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors
AUDIO_VAE_URL=https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors
LLM_URL=https://huggingface.co/leejet/MiniMax-H3-GGUF/resolve/main/qwen3vl_32b_minimax_h3-Q4_K_M.gguf
```

Notes:

- The text encoder must be the MiniMax-H3 variant of Qwen3-VL-32B (50
  language layers, exported without the final language-model normalization).
- Omitting `AUDIO_VAE_URL` still runs the joint diffusion model but produces
  video without a decoded audio track.
- The model repositories require accepting the MiniMax H3 Community License
  and providing a `HF_TOKEN`.
- Size: diffusion model ~18.8 GB (Q4_K_M), video VAE ~5.2 GB, audio VAE ~605 MB,
  text encoder ~11.4 GB (Q4_K_M).

## Using the pre-built GHCR image

The compose file is tagged for the GitHub Container Registry:

```bash
docker compose pull
docker compose up -d
```

Image: `ghcr.io/dontdrinkandroot/stable-diffusion-cpp.docker:latest`

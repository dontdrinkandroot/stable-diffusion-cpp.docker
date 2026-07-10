# sdcpp-flux-klein-9b.docker

Docker image for running **FLUX.2-klein-9B** with
[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) (CUDA variant).
Models are downloaded automatically on first startup via rclone and cached in a
named volume for subsequent runs.

## Requirements

- NVIDIA GPU + NVIDIA drivers
- Docker with GPU support (Docker 19.03+ with `--gpus` or Docker Compose `deploy.resources`)
- HuggingFace token with access to the gated
  [`black-forest-labs/FLUX.2-dev`](https://huggingface.co/black-forest-labs/FLUX.2-dev)
  repository (needed for the VAE file `ae.safetensors`)

  To get access:
  1. Create a token at https://huggingface.co/settings/tokens
  2. Accept the FLUX Non-Commercial License at
     https://huggingface.co/black-forest-labs/FLUX.2-dev

## Running locally

### 1. Set your HuggingFace token

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

### 2. Build and start

```bash
docker compose up -d --build
```

The first start downloads three model files (~15 GB total) into the `models`
named volume:

| Model | Repo | File | Size |
|-------|------|------|------|
| Diffusion model (Q6_K) | `unsloth/FLUX.2-klein-9B-GGUF` | `flux-2-klein-9b-Q6_K.gguf` | 7.87 GB |
| VAE | `black-forest-labs/FLUX.2-dev` | `ae.safetensors` | 336 MB |
| Text encoder / LLM (Q6_K) | `unsloth/Qwen3-8B-GGUF` | `Qwen3-8B-Q6_K.gguf` | 6.73 GB |

Downloads use rclone with parallel chunked streams (see `RCLONE_STREAMS` below).

### 3. Use the server

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
| `HF_TOKEN` | (empty) | HuggingFace token; required for the gated VAE repo |
| `MODEL_DIR` | `/models` | Directory for model files (mapped to a volume) |
| `PORT` | `1234` | sd-server HTTP port |

## Using the pre-built GHCR image

The compose file is tagged for the GitHub Container Registry:

```bash
docker compose pull
docker compose up -d
```

Image: `ghcr.io/philipsorst/sdcpp-flux-klein-9b.docker:latest`

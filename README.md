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
defaults — configure at least one of `DIFFUSION_MODEL_URL`, `VAE_URL`, or
`LLM_URL` for the models you want to use.

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
| `LLM_URL` | *(none — must be set)* | URL for the text encoder / LLM file |

Local filenames are derived from the URL via `basename` (e.g. `.../foo.gguf` → `$MODEL_DIR/foo.gguf`).

### Example: FLUX.2-klein-9B

```env
DIFFUSION_MODEL_URL=https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF/resolve/main/flux-2-klein-9b-Q6_K.gguf
VAE_URL=https://huggingface.co/black-forest-labs/FLUX.2-dev/resolve/main/ae.safetensors
LLM_URL=https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q6_K.gguf
```

## Using the pre-built GHCR image

The compose file is tagged for the GitHub Container Registry:

```bash
docker compose pull
docker compose up -d
```

Image: `ghcr.io/dontdrinkandroot/stable-diffusion-cpp.docker:latest`

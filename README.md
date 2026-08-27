# stable-diffusion-cpp.docker

Generic Docker image for running [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) (CUDA variant).
Models are downloaded automatically on first startup — via aria2c (URL-based) or
`hf download` (HuggingFace spec-based) — and cached in a named volume for subsequent runs.

## Requirements

- NVIDIA GPU + NVIDIA drivers
- Docker with GPU support (Docker 19.03+ with `--gpus` or Docker Compose `deploy.resources`)
- HuggingFace token (**required** if any model URL points to a gated repo)

## Configuration

### 1. Set model URLs

You **must** set the model URLs via environment variables. There are no built-in
defaults — configure at least one of `DIFFUSION_MODEL_URL`, `VAE_URL`,
`AUDIO_VAE_URL`, or `LLM_URL` (or their `HF_*` equivalents, see below) for the
models you want to use.

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
| `HF_DIFFUSION_MODEL` | *(none)* | HuggingFace spec `org/repo/file` for the diffusion model (downloaded via `hf download` instead of aria2c). Mutually exclusive with `DIFFUSION_MODEL_URL`. |
| `HF_VAE` | *(none)* | HuggingFace spec `org/repo/file` for the VAE. Mutually exclusive with `VAE_URL`. |
| `HF_AUDIO_VAE` | *(none)* | HuggingFace spec `org/repo/file` for the audio VAE. Mutually exclusive with `AUDIO_VAE_URL`. |
| `HF_LLM` | *(none)* | HuggingFace spec `org/repo/file` for the text encoder / LLM. Mutually exclusive with `LLM_URL`. |
| `HF_LORAS` | *(none)* | Comma-separated (no spaces) list of HuggingFace specs `org/repo/file` downloaded via `hf download` into `$LORA_DIR`. |
| `DIFFUSION_FA` | *(empty)* | Set to `1` to enable `--diffusion-fa` (Flash Attention for diffusion model) |
| `OFFLOAD_TO_CPU` | *(empty)* | Set to `1` to enable `--offload-to-cpu` (offload to CPU when VRAM is insufficient) |
| `CFG_SCALE` | *(empty)* | Sets `--cfg-scale` value (classifier-free guidance scale) |
| `STEPS` | *(empty)* | Sets `--steps` value (number of sampling steps) |
| `DISABLE_AUTO_RESIZE_REF_IMAGE` | *(empty)* | Set to `1` to enable `--disable-auto-resize-ref-image` |
| `SAMPLING_METHOD` | *(empty)* | Sets `--sampling-method` value (e.g. `euler`, `dpm++2m`, `res_multistep`). Value is forwarded verbatim to sd-server; no validation. |
| `SCHEDULER` | *(empty)* | Sets `--scheduler` value (e.g. `simple`, `karras`, `discrete`). Value is forwarded verbatim to sd-server; no validation. |
| `FLOW_SHIFT` | *(empty)* | Sets `--flow-shift` value (numeric, for Flow models like SD3.x/WAN). Value is forwarded verbatim to sd-server; no validation. |
| `FPS` | *(empty)* | Sets `--fps` value (video framerate). Value is forwarded verbatim to sd-server; no validation. |
| `VIDEO_FRAMES` | *(empty)* | Sets `--video-frames` value (number of frames for video generation). Value is forwarded verbatim to sd-server; no validation. |
| `WIDTH` | *(empty)* | Sets `--width` value (image width in pixels). Value is forwarded verbatim to sd-server; no validation. |
| `HEIGHT` | *(empty)* | Sets `--height` value (image height in pixels). Value is forwarded verbatim to sd-server; no validation. |
| `MAX_VRAM` | *(empty)* | Sets `--max-vram` value (e.g. `6` or `cuda0=6`; `-1` auto-detects free VRAM). Value is forwarded verbatim to sd-server; no validation. |
| `VERBOSE` | *(empty)* | Set to `1` to enable `-v` (verbose logging). |
| `AUTO_FIT` | *(empty)* | Set to `1` to enable `--auto-fit` (auto pick device placements from model size and per-device memory budgets). |

Local filenames are derived from the URL via `basename` (e.g. `.../foo.gguf` → `$MODEL_DIR/foo.gguf`).
HF specs are resolved via `hf download REPO FILE --local-dir $MODEL_DIR`, preserving
subdirectories in the file path (e.g. `org/repo/split_files/vae/foo.safetensors` →
`$MODEL_DIR/split_files/vae/foo.safetensors`).
HF downloads log their own progress in docker logs (`[download] 42% (3.3 GiB / 7.9 GiB)
45.2 MiB/s ETA 1m40s`, every 10 seconds — tqdm is auto-disabled on non-TTY output; bytes
only when the file size cannot be determined, e.g. gated repos without `HF_TOKEN`).

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

### Example: Krea 2 (turbo distill LoRA, HF specs)

Krea 2 uses the Krea2 diffusion transformer, the Wan2.1 VAE, and Qwen3-VL-4B as
the text encoder. This example runs the Raw base model with the
`krea2-turbo-distill` LoRA applied (extracts Turbo behavior from the Raw→Turbo
weight delta) — so the diffusion model is the **Raw** checkpoint, not Turbo.
All components are given as `HF_*` specs (`org/repo/file`) and downloaded via
`hf download` instead of aria2c:

```env
HF_DIFFUSION_MODEL=realrebelai/KREA-2_GGUFs/BASE/Krea-2-Base-Q4_K_M.gguf
HF_VAE=Comfy-Org/Wan_2.1_ComfyUI_repackaged/split_files/vae/wan_2.1_vae.safetensors
HF_LLM=Qwen/Qwen3-VL-4B-Instruct-GGUF/Qwen3VL-4B-Instruct-Q4_K_M.gguf
HF_LORAS=TheDivergentAI/krea2-turbo-distill-lora/krea2_turbo_distill_r128.safetensors
STEPS=8
CFG_SCALE=0
DIFFUSION_FA=1
```

Notes:

- The LoRA is downloaded into `$LORA_DIR` (`/loras`) and referenced at request
  time via the sd-server API (e.g. `path: "krea2_turbo_distill_r128.safetensors"`).
- Turbo-style sampling needs 8 steps with CFG disabled (`CFG_SCALE=0`).
- The Raw GGUF is ~5.5 GB (Q4_K_M); the distill LoRA is ~0.94 GB (rank 128).
- `HF_TOKEN` is required — the Krea 2 weights are under the Krea 2 Community License.

## Using the pre-built GHCR image

The compose file is tagged for the GitHub Container Registry:

```bash
docker compose pull
docker compose up -d
```

Image: `ghcr.io/dontdrinkandroot/stable-diffusion-cpp.docker:latest`

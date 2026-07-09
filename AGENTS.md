# AGENTS.md

## Project Overview

Docker image for running **FLUX.2-klein-9B** with **stable-diffusion.cpp** (CUDA variant).
Uses the pre-built upstream CUDA image and adds an entrypoint that downloads model weights
on first startup using **rclone** for fast parallel chunked downloads.

## Model Download (rclone)

Models are downloaded via `rclone copyurl --urls` (CSV batch mode):

- **`--multi-thread-streams`** (default `4`, configurable via `RCLONE_STREAMS`): splits each
  large file into N parallel HTTP Range-request chunks. HuggingFace CDN supports Range.
- **`--transfers 3`**: downloads all 3 model files concurrently.
- **`--no-clobber`**: skips files already present (idempotent restarts).
- **`--header-download "Authorization: Bearer $HF_TOKEN"`**: auth for gated repos (sent on
  all requests; non-gated repos accept it without error).
- rclone is installed from the official precompiled binary
  (`https://downloads.rclone.org/rclone-current-linux-amd64.zip`), not from apt.

## Project Structure

```
.
├── Dockerfile          # FROM upstream CUDA image; installs rclone + entrypoint
├── entrypoint.sh       # Downloads models via rclone, then execs sd-server
├── docker-compose.yml  # Port 1234, GPU, models volume, HF_TOKEN
├── .dockerignore
└── AGENTS.md
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HF_TOKEN` | (empty) | HuggingFace token; required for gated FLUX.2-dev VAE repo |
| `MODEL_DIR` | `/models` | Directory for model files (mapped to a volume) |
| `PORT` | `1234` | sd-server HTTP port |
| `RCLONE_STREAMS` | `4` | Parallel chunked download streams per file |

## Model Files

| Model | Repo | File | Size |
|-------|------|------|------|
| Diffusion model (Q6_K) | `unsloth/FLUX.2-klein-9B-GGUF` | `flux-2-klein-9b-Q6_K.gguf` | 7.87 GB |
| VAE | `black-forest-labs/FLUX.2-dev` | `ae.safetensors` | 336 MB |
| Text encoder / LLM (Q6_K) | `unsloth/Qwen3-8B-GGUF` | `Qwen3-8B-Q6_K.gguf` | 6.73 GB |

> **Note:** `black-forest-labs/FLUX.2-dev` is a gated repo. Requires accepting the
> FLUX Non-Commercial License and providing `HF_TOKEN`.

## Reference

### Upstream stable-diffusion.cpp

- Repository: https://github.com/leejet/stable-diffusion.cpp
- CUDA Docker image (pre-built): `ghcr.io/leejet/stable-diffusion.cpp:master-cuda`
- All pre-built images: https://github.com/leejet/stable-diffusion.cpp/pkgs/container/stable-diffusion.cpp
- Build docs: https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/build.md
- Docker docs: https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/docker.md
- FLUX.2 usage guide: https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/flux2.md
- Performance guide: https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/performance.md

### Upstream Dockerfiles (for reference)

- CPU: https://github.com/leejet/stable-diffusion.cpp/blob/master/docker/Dockerfile
- CUDA: https://github.com/leejet/stable-diffusion.cpp/blob/master/docker/Dockerfile.cuda

### Model Downloads (HuggingFace)

- FLUX.2-klein-9B GGUF (all quantizations): https://huggingface.co/unsloth/FLUX.2-klein-9B-GGUF
- FLUX.2-klein-9B GGUF (leejet, smaller set): https://huggingface.co/leejet/FLUX.2-klein-9B-GGUF
- FLUX.2-dev (VAE source, gated): https://huggingface.co/black-forest-labs/FLUX.2-dev
- Qwen3-8B GGUF (text encoder): https://huggingface.co/unsloth/Qwen3-8B-GGUF
- FLUX.2-small-decoder (alternative VAE): https://huggingface.co/black-forest-labs/FLUX.2-small-decoder

### FLUX.2-klein Model Card

- Official announcement: https://huggingface.co/black-forest-labs/FLUX.2-klein-9B
- License: `flux-non-commercial-license`
- Variants: klein-4B (Apache 2.0), klein-9B (non-commercial), klein-base-4B, klein-base-9B

### Server CLI Flags (sd-server)

Key flags used in this project:

```
--diffusion-model <path>   # FLUX.2-klein-9B GGUF file
--vae <path>               # ae.safetensors (FLUX.2-dev VAE)
--llm <path>               # Qwen3-8B GGUF (text encoder)
--port <port>              # HTTP server port (default: 1234)
--diffusion-fa             # Flash Attention for diffusion model
--offload-to-cpu           # Offload to CPU when VRAM is insufficient
--cfg-scale 1.0            # CFG scale (1.0 recommended for klein)
--steps 4                  # Inference steps (4 for distilled klein, 20 for base)
```

### rclone

- Install (precompiled binary): https://rclone.org/install/
- `copyurl` command docs: https://rclone.org/commands/rclone_copyurl/
- Global flags (`--multi-thread-streams`, `--transfers`, `--header-download`, etc.): https://rclone.org/flags/
- Downloads page: https://rclone.org/downloads/

## Self-Update Instruction

This guidelines file is a living document and MUST be actively maintained by the LLM Agent.

* **Trigger:** Whenever significant changes are made to the tech stack, project structure, coding guidelines, or key features, the LLM Agent MUST immediately update this file (`AGENTS.md`) to reflect the current state of the project.
* **Content:** 
    * Add any information that could have helped the agent to solve the task more efficiently or in fewer steps.
    * Remove outdated, obsolete, or incorrect information.
    * Ensure all tech stack versions and library names are accurate.
    * Make sure the most important features are clearly documented.
    * Keep the project structure up to date so that the most important files and directories are visible at a glance.
* **Proactivity:** Do not wait for explicit instructions to update these guidelines if you identify a discrepancy between the guidelines and the actual codebase.

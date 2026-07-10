# AGENTS.md

## Project Overview

Docker image for running **FLUX.2-klein-9B** with **stable-diffusion.cpp** (CUDA variant).
Uses the pre-built upstream CUDA image and adds an entrypoint that downloads model weights
on startup using **aria2c** with resume support.

## Instructions

* **Get back to the user:** When seemingly stuck, when an approach does not work as expected, or when new decisions have to be taken, the LLM Agent MUST stop and get back to the user with the situation and options instead of continuing with assumptions. Do not silently pivot to a different approach.

## Model Download (aria2c)

Models are downloaded via `aria2c` with an input file listing all 3 URLs:

- **`-c` (continue)**: resumes partial downloads via a `.aria2` control file + HTTP Range
  requests. An interrupted run continues where it left off on next start.
- **`-x16 -s16`**: 16 parallel connections per file (chunked download).
- **`-j3`**: downloads all 3 model files concurrently.
- **`--header="Authorization: Bearer $HF_TOKEN"`**: auth header sent on all requests
  (required for the gated FLUX.2-dev VAE repo).
- **`-i` (input file)**: each URL is paired with an explicit `out=` filename so the
  output name is controlled regardless of CDN redirects.
- **Retry loop**: the download is wrapped in a retry loop (default 3 attempts, configurable
  via `MAX_ATTEMPTS`). On failure, aria2c is re-invoked; `-c` ensures no wasted bandwidth.
- aria2 is installed via `apt-get` (Debian package `aria2`).

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── docker-publish.yml  # CI: build & push image to GHCR
├── Dockerfile          # FROM upstream CUDA image; installs aria2 + entrypoint
├── entrypoint.sh       # Downloads models via aria2c, then execs sd-server
├── docker-compose.yml  # Port 1234, GPU, models volume, HF_TOKEN
├── docs/
│   └── vastai.md       # Guide for running on vast.ai GPU marketplace
├── .dockerignore
└── AGENTS.md
```

## CI/CD (GitHub Actions)

The `.github/workflows/docker-publish.yml` workflow builds and pushes the
image to the GitHub Container Registry (GHCR).

- **Trigger:** push to `main` (when `Dockerfile`, `entrypoint.sh`, or the
  workflow itself changes), plus manual `workflow_dispatch`.
- **Registry:** `ghcr.io/philipsorst/sdcpp-flux-klein-9b.docker`
- **Tags produced:** `latest` and `sha-<short>` (e.g. `sha-ea0fba2`).
- **Platform:** `linux/amd64` only (upstream CUDA base is amd64; all target
  hosts are x86_64 NVIDIA GPUs).
- **Auth:** uses the auto-provisioned `GITHUB_TOKEN` with `packages: write`.
- **No GPU needed for build** — the Dockerfile only installs `aria2` and copies
  the entrypoint; the CUDA runtime comes from the upstream base image.

### One-time: make the GHCR package public

After the first workflow run, the package defaults to **private**. Since Vast.ai
and anonymous pulls need access, flip it to public:

1. Go to `https://github.com/users/philipsorst/packages/container/sdcpp-flux-klein-9b.docker`
2. **Package settings** → **Danger Zone** → **Change visibility** → **Public**

Alternatively use the CLI:

```bash
gh api --method PATCH /user/packages/container/sdcpp-flux-klein-9b.docker/visibility \
  -f visibility=public
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HF_TOKEN` | (empty) | HuggingFace token; **required** (gated FLUX.2-dev VAE repo) |
| `MODEL_DIR` | `/models` | Directory for model files (mapped to a volume) |
| `PORT` | `1234` | sd-server HTTP port |
| `MAX_ATTEMPTS` | `3` | Max download retry attempts before failing |

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

### aria2c

- Install: `apt-get install aria2` (Debian package `aria2`)
- aria2 docs: https://aria2.github.io/manual/en/html/aria2c.html
- Key flags: `-c` (continue), `-x` (max connections per server), `-s` (split), `-j` (concurrent downloads),
  `-i` (input file), `--header`, `-d` (dir), `-k` (min split size)
- Downloads page: https://aria2.github.io/

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


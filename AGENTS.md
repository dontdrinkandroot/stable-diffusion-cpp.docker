# AGENTS.md

## Project Overview

Generic Docker image for running **stable-diffusion.cpp** (CUDA variant).
Uses the pre-built upstream CUDA image and adds an entrypoint that downloads model weights
on startup using **aria2c** with resume support. Model URLs are configured via environment
variables — there are no hardcoded defaults.

## Instructions

* **Get back to the user:** When seemingly stuck, when an approach does not work as expected, or when new decisions have to be taken, the LLM Agent MUST stop and get back to the user with the situation and options instead of continuing with assumptions. Do not silently pivot to a different approach.
 
## Tool Usage

Use the dedicated tools; the `bash` tool is ONLY for actually executing
  commands (running `bin/validate-backend`/`bin/validate-frontend`, PHPUnit, PHPStan,
  `composer`/`pnpm`, `git`, migrations). Never use `bash` for reading, searching, or
  listing — use the dedicated tools:
    - Find files by pattern -> `glob` (never `find` / `ls`)
    - Search file contents -> `grep` (never shell `grep`/`rg`, except `rg -c` for counts)
    - Read a file OR list a directory's entries -> `read` (it accepts directories; never `cat`/`head`/`ls`)
    - Edit files -> `edit` / `write` (never `sed` / `awk` / `echo`)
  For several independent lookups, fire parallel dedicated-tool calls in one message
  instead of chaining shell commands.
  If the dedicated tools seem stuck (e.g. `glob` finds nothing in an unfamiliar `vendor/`
  tree), `read` the directory itself or widen the glob — do NOT fall back to `find`/`ls`.
  If an exploration still cannot be done, ask the user instead of guessing with `bash`.

## Model Download (aria2c)

Models are downloaded via `aria2c` with an input file listing all 3 URLs:

- **`-c` (continue)**: resumes partial downloads via a `.aria2` control file + HTTP Range
  requests. An interrupted run continues where it left off on next start.
- **`-x16 -s16`**: 16 parallel connections per file (chunked download).
- **`-j3`**: downloads all 3 model files concurrently.
- **`--header "Authorization: Bearer $HF_TOKEN"`**: auth header sent on all requests
  (required for the gated FLUX.2-dev VAE repo). Passed as a bash array element so the
  header value stays a single argument regardless of spaces.
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
├── Dockerfile          # FROM upstream CUDA image; installs aria2, curl, sshd StrictModes fix + entrypoint; HEALTHCHECK
├── entrypoint.sh       # Downloads models via aria2c, then execs sd-server
├── docker-compose.yml  # Port 1234, GPU, models + loras volumes, HF_TOKEN
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
- **Registry:** `ghcr.io/dontdrinkandroot/stable-diffusion-cpp.docker`
- **Tags produced:** `latest` and `sha-<short>` (e.g. `sha-ea0fba2`).
- **Platform:** `linux/amd64` only (upstream CUDA base is amd64; all target
  hosts are x86_64 NVIDIA GPUs).
- **Auth:** uses the auto-provisioned `GITHUB_TOKEN` with `packages: write`.
- **No GPU needed for build** — the Dockerfile only installs `aria2` and copies
  the entrypoint; the CUDA runtime comes from the upstream base image.

### Image retention (automatic cleanup)

After each successful build, a `cleanup` job runs
`snok/container-retention-policy@v3.1.0` to prune old GHCR image versions,
keeping only the **5 newest** tagged versions (`cut-off: 0s` +
`keep-n-most-recent: 5`). This prevents the registry from accumulating stale
`sha-<short>` versions over time. Deleted versions remain restorable for 30
days via GitHub's grace period.

### One-time: make the GHCR package public

After the first workflow run, the package defaults to **private**. Since Vast.ai
and anonymous pulls need access, flip it to public:

1. Go to `https://github.com/users/dontdrinkandroot/packages/container/stable-diffusion-cpp.docker`
2. **Package settings** → **Danger Zone** → **Change visibility** → **Public**

Alternatively use the CLI:

```bash
gh api --method PATCH /user/packages/container/stable-diffusion-cpp.docker/visibility \
  -f visibility=public
```

### One-time: grant the repository Admin role on the package

The cleanup job uses the auto-provisioned `GITHUB_TOKEN` to delete old image
versions. For this to work, the repository must have the **Admin** role on the
GHCR package (write permission alone is not sufficient for deletion):

1. Go to the package page → **Package settings** → **Manage Actions access**
2. Add the repository `dontdrinkandroot/stable-diffusion-cpp.docker`
3. Set its role to **Admin**

This step can only be done after the first build creates the package.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HF_TOKEN` | (empty) | HuggingFace token; **required** for gated repos. Optional if all URLs point to public repos. |
| `MODEL_DIR` | `/models` | Directory for model files (mapped to a volume) |
| `LORA_DIR` | `/loras` | Directory for LoRA files (mapped to a volume; upload via SSH/`docker cp`) |
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
| `SAMPLING_METHOD` | *(empty)* | Sets `--sampling-method` value (e.g. `euler`, `dpm++2m`, `res_multistep`). Value is forwarded verbatim to sd-server; no validation. |
| `SCHEDULER` | *(empty)* | Sets `--scheduler` value (e.g. `simple`, `karras`, `discrete`). Value is forwarded verbatim to sd-server; no validation. |
| `FLOW_SHIFT` | *(empty)* | Sets `--flow-shift` value (numeric, for Flow models like SD3.x/WAN). Value is forwarded verbatim to sd-server; no validation. |

Local filenames are derived from the URL via `basename` (e.g. `.../foo.gguf` → `$MODEL_DIR/foo.gguf`).

## Model Files (Example: FLUX.2-klein-9B)

| Model | Repo | File | Size |
|-------|------|------|------|
| Diffusion model (Q6_K) | `unsloth/FLUX.2-klein-9B-GGUF` | `flux-2-klein-9b-Q6_K.gguf` | 7.87 GB |
| VAE | `black-forest-labs/FLUX.2-dev` | `ae.safetensors` | 336 MB |
| Text encoder / LLM (Q6_K) | `unsloth/Qwen3-8B-GGUF` | `Qwen3-8B-Q6_K.gguf` | 6.73 GB |

> **Note:** `black-forest-labs/FLUX.2-dev` is a gated repo. Requires accepting the
> FLUX Non-Commercial License and providing `HF_TOKEN`.

## Model Files (Example: MiniMax-H3)

MiniMax-H3 jointly generates video and stereo audio. The server needs FOUR
components wired separately via `--diffusion-model`, `--vae`, `--audio-vae`,
and `--llm`. The upstream doc is `docs/minimax_h3.md`.

| Component | Repo | File | Size |
|-------|------|------|------|
| Diffusion model (Q4_K_M) | `leejet/MiniMax-H3-GGUF` | `minimax_h3_fl2va-Q4_K_M.gguf` | ~18.8 GB |
| Video VAE | `Comfy-Org/MiniMax-H3` | `minimax_h3_video_vae_fp16.safetensors` | ~5.2 GB |
| Audio VAE | `Comfy-Org/MiniMax-H3` | `minimax_h3_audio_vae_fp32.safetensors` | ~605 MB |
| Text encoder (Q4_K_M) | `leejet/MiniMax-H3-GGUF` | `qwen3vl_32b_minimax_h3-Q4_K_M.gguf` | ~11.4 GB |

> **Note:** The text encoder must be the MiniMax-H3 variant of Qwen3-VL-32B
> (truncated to 50 language layers, exported without the final language-model
> normalization). The H3 repos require accepting the MiniMax H3 Community
> License and providing `HF_TOKEN`. Omitting `AUDIO_VAE_URL` still runs the
> joint diffusion model but produces video without a decoded audio track.

## Healthcheck

The Dockerfile defines a `HEALTHCHECK` that probes the sd-server's
`/sdcpp/v1/capabilities` endpoint via `curl --fail`:

```
HEALTHCHECK --interval=30s --timeout=10s --start-period=1800s --retries=3 \
    CMD curl --fail http://localhost:${PORT:-1234}/sdcpp/v1/capabilities || exit 1
```

- **`start-period=1800s` (30 min):** gives the container a grace period that
  covers the one-time ~15 GB model download on first start. During this window,
  healthcheck failures do not count against the container. On subsequent starts
  (models already in the volume), the server is ready much faster.
- **`curl`** is installed alongside `aria2` in the Dockerfile.
- The healthcheck respects the `PORT` env var (default `1234`).

## SSH StrictModes Fix (for vast.ai)

When using `--ssh` mode on vast.ai, the platform builds an overlay image that
installs `openssh-server` and configures sshd. Vast.ai's provisioning includes:

```
sed -i "s/StrictModes yes/StrictModes no/g" /etc/ssh/sshd_config
```

However, Ubuntu 24.04's default `sshd_config` ships with `#StrictModes yes`
(commented out). The sed only changes it to `#StrictModes no` — **still
commented** — so `StrictModes` falls back to its default of `yes`. This causes
sshd to reject `/root/.ssh/authorized_keys` with:
`Authentication refused: bad ownership or modes for file /root/.ssh/authorized_keys`.

**Fix:** The Dockerfile creates a drop-in config at
`/etc/ssh/sshd_config.d/99-strictmodes-no.conf` with `StrictModes no`. This
file:
- Is loaded via the `Include /etc/ssh/sshd_config.d/*.conf` directive in
  Ubuntu 24.04's `sshd_config`
- Is not a conffile, so it survives vast.ai's `openssh-server` installation
- Pre-creates `/root/.ssh` with `700` permissions as belt-and-suspenders

This was verified by simulating the full vast.ai overlay build process and
confirming `sshd -T` reports `strictmodes no`.

## Reference

### Upstream stable-diffusion.cpp

- Repository: https://github.com/leejet/stable-diffusion.cpp
- CUDA Docker image (pre-built): `ghcr.io/leejet/stable-diffusion.cpp:master-cuda`
- All pre-built images: https://github.com/leejet/stable-diffusion.cpp/pkgs/container/stable-diffusion.cpp
- Build docs: https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/build.md
- Docker docs: https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/docker.md
- MiniMax-H3 guide: https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/minimax_h3.md
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
- MiniMax-H3 GGUF (all quantizations): https://huggingface.co/leejet/MiniMax-H3-GGUF
- MiniMax-H3 weights (VAE sources, license required): https://huggingface.co/Comfy-Org/MiniMax-H3
- MiniMax-H3 (official, gated): https://huggingface.co/MiniMaxAI/MiniMax-H3

### FLUX.2-klein Model Card

- Official announcement: https://huggingface.co/black-forest-labs/FLUX.2-klein-9B
- License: `flux-non-commercial-license`
- Variants: klein-4B (Apache 2.0), klein-9B (non-commercial), klein-base-4B, klein-base-9B

### Server CLI Flags (sd-server)

Key flags used in this project:

```
--diffusion-model <path>   # Diffusion model GGUF file
--vae <path>               # VAE file
--audio-vae <path>         # Audio VAE file (conditional: AUDIO_VAE_URL; e.g. MiniMax-H3)
--llm <path>               # Text encoder / LLM GGUF file
--port <port>              # HTTP server port (default: 1234)
--diffusion-fa             # Flash Attention for diffusion model (conditional: DIFFUSION_FA=1)
--offload-to-cpu           # Offload to CPU when VRAM is insufficient (conditional: OFFLOAD_TO_CPU=1)
--cfg-scale <value>        # Classifier-free guidance scale (conditional: CFG_SCALE)
--steps <value>            # Number of sampling steps (conditional: STEPS)
--disable-auto-resize-ref-image  # Disable auto-resize of reference image (conditional: DISABLE_AUTO_RESIZE_REF_IMAGE=1)
--sampling-method <value>  # Sampling method (conditional: SAMPLING_METHOD)
--scheduler <value>        # Denoiser sigma scheduler (conditional: SCHEDULER)
--flow-shift <value>       # Shift value for Flow models like SD3.x/WAN (conditional: FLOW_SHIFT)
--lora-model-dir <path>   # LoRA directory (default: /loras; upload LoRAs here via SSH)
```

### LoRA Directory

The entrypoint creates `/loras` (configurable via `LORA_DIR`) and passes it to
`sd-server` via `--lora-model-dir`. Upload LoRA files (`.gguf` / `.safetensors`)
into this directory at runtime — no restart needed:

```bash
# Via docker cp
docker cp my-lora.gguf sd-server:/loras/

# Via SSH (Vast.ai)
scp -P SSH_PORT my-lora.gguf root@SSH_HOST:/loras/
```

The directory is backed by a named volume (`loras`) in `docker-compose.yml` so
files persist across container restarts. On Vast.ai, link a persistent volume at
`/loras` to preserve LoRAs across instance recreations.

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


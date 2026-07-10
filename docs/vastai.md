# Running on Vast.ai

[Vast.ai](https://vast.ai) is a marketplace for affordable GPU cloud computing.
This guide explains how to run the FLUX.2-klein-9B Docker image on a rented
GPU instance.

---

## Prerequisites

1. **Vast.ai account** – Sign up at [cloud.vast.ai](https://cloud.vast.ai), verify
   your email, and add credit (minimum $5).

2. **HuggingFace token** – Required to download the VAE from the gated
   `black-forest-labs/FLUX.2-dev` repo:
   1. Accept the FLUX Non-Commercial License at
      <https://huggingface.co/black-forest-labs/FLUX.2-dev>
   2. Create a read-access token at
      <https://huggingface.co/settings/tokens>

3. **SSH key** (optional, for SSH access) – Generate a key pair and register the
   public key under
   [Keys](https://cloud.vast.ai/manage-keys/).

---

## GPU Requirements

| Component | Size |
|-----------|------|
| Diffusion model (Q6\_K GGUF) | ~7.9 GB |
| Text encoder – Qwen3-8B (Q6\_K GGUF) | ~6.7 GB |
| VAE (ae.safetensors) | ~336 MB |
| **Total model VRAM (if fully loaded)** | **~15 GB** |

Recommended GPUs:

| GPU | VRAM | Fits? |
|-----|------|-------|
| RTX 3090 / 4090 | 24 GB | Yes – full load |
| RTX 4080 | 16 GB | Yes – tight; `--offload-to-cpu` may be needed |
| RTX 3080 / 4070 Ti | 12 GB | Partial – requires `--offload-to-cpu` |

The entrypoint already passes `--offload-to-cpu`, so models that don't fit in
VRAM spill to system RAM. Make sure the host has enough system RAM (32 GB+ is
safe) if you're using a lower-VRAM GPU.

---

## Disk Space

The container needs room for:

- Docker image layers (~3–4 GB)
- Model downloads (~15 GB)
- Generated images / working space

**Allocate at least 30 GB of disk.** 40 GB is recommended for headroom.
Disk size is set at creation time and **cannot be changed later**.

---

## Option A: CLI Workflow

### 1. Install the Vast.ai CLI

```bash
pip install vastai
```

Verify:

```bash
vastai --help
```

### 2. Authenticate

Generate an API key on the
[Keys page](https://cloud.vast.ai/manage-keys/), then:

```bash
vastai set api-key YOUR_API_KEY
```

Confirm it works:

```bash
vastai show user
```

### 3. (Optional) Register your SSH key

```bash
vastai create ssh-key ~/.ssh/id_ed25519.pub
```

This is only needed if you want SSH access. With the **Entrypoint** launch mode
(used below), SSH is not injected and the container runs the image's own
entrypoint directly.

### 4. Search for GPU offers

Find a suitable single-GPU machine with enough VRAM and disk:

```bash
# RTX 3090 or 4090, 24 GB VRAM, verified, reliable
vastai search offers \
  'gpu_name in ["RTX 3090","RTX 4090"] num_gpus=1 gpu_ram>=20 verified=true reliability>0.98 rentable=true' \
  -o 'dlperf_usd-'
```

Other useful queries:

```bash
# Any GPU with >=16 GB VRAM, sorted by price
vastai search offers \
  'num_gpus=1 gpu_ram>=16 verified=true rentable=true' \
  -o 'dph+'

# Interruptible (spot) instances for lower cost
vastai search offers \
  'gpu_name in ["RTX 3090","RTX 4090"] num_gpus=1 verified=true rentable=true' \
  -t bid -o 'dph+'
```

Note the **offer ID** (first column) from the results.

### 5. Create the instance

Use **Entrypoint** launch mode (not `--ssh` or `--jupyter`) so the image's
own `/entrypoint.sh` runs directly. This is critical: SSH/Jupyter launch modes
override the image entrypoint, which would prevent the model download and
server startup from running.

```bash
vastai create instance OFFER_ID \
  --image ghcr.io/philipsorst/sdcpp-flux-klein-9b.docker:latest \
  --disk 40 \
  --env '-e HF_TOKEN=hf_your_token_here -p 1234:1234' \
  --onstart-cmd '/entrypoint.sh'
```

| Flag | Purpose |
|------|---------|
| `--image` | The pre-built image from GHCR |
| `--disk 40` | 40 GB disk (cannot be changed later) |
| `-e HF_TOKEN=...` | HuggingFace token (required for VAE download) |
| `-p 1234:1234` | Expose the sd-server HTTP port |
| `--onstart-cmd '/entrypoint.sh'` | Run the entrypoint script on start |

<details>
<summary>Using a private registry?</summary>

If you push the image to a private registry, add `--login`:

```bash
vastai create instance OFFER_ID \
  --image your-registry.com/sdcpp-flux-klein-9b:latest \
  --login '-u USER -p PASS your-registry.com' \
  --disk 40 \
  --env '-e HF_TOKEN=hf_your_token_here -p 1234:1234' \
  --onstart-cmd '/entrypoint.sh'
```

</details>

**Interruptible (spot) instance** – cheaper, but can be terminated at any time:

```bash
vastai create instance OFFER_ID \
  --image ghcr.io/philipsorst/sdcpp-flux-klein-9b.docker:latest \
  --disk 40 \
  --env '-e HF_TOKEN=hf_your_token_here -p 1234:1234' \
  --onstart-cmd '/entrypoint.sh' \
  --bid_price 0.20
```

### 6. Wait for the instance to start

```bash
vastai show instance INSTANCE_ID
```

The `status` field progresses through:

| Status | Meaning |
|--------|---------|
| `loading` | Docker image is being pulled |
| `running` | Instance is up; entrypoint is executing |
| `exited` | Container crashed — check logs |

The first start downloads ~15 GB of model files via aria2c. This can take
5–30 minutes depending on the host's download bandwidth. Monitor progress:

```bash
vastai logs INSTANCE_ID
```

### 7. Find the mapped port

Vast.ai maps internal ports to random external ports. Find the mapping for
port 1234:

```bash
vastai show instance INSTANCE_ID
```

Look for a line like:

```
PUBLIC_IP:EXTERNAL_PORT -> 1234/tcp
```

Or check the **IP Port Info** popup on the instance card in the web console.

You can also read the `VAST_TCP_PORT_1234` environment variable inside the
container to get the external port programmatically.

### 8. Access the server

Once the entrypoint logs show `=== Starting sd-server ===`, the server is
ready. Use the mapped address:

```bash
curl http://PUBLIC_IP:EXTERNAL_PORT/health
```

Or open `http://PUBLIC_IP:EXTERNAL_PORT` in a browser (see the
[sd-server API docs](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/docker.md)
for available endpoints).

To make the **Open** button in the Vast.ai console link to the server, set
`OPEN_BUTTON_PORT`:

```bash
vastai create instance OFFER_ID \
  --image ghcr.io/philipsorst/sdcpp-flux-klein-9b.docker:latest \
  --disk 40 \
  --env '-e HF_TOKEN=hf_your_token_here -e OPEN_BUTTON_PORT=1234 -p 1234:1234' \
  --onstart-cmd '/entrypoint.sh'
```

### 9. Stop or destroy the instance

**Stop** (pauses GPU billing, disk charges continue, models are preserved):

```bash
vastai stop instance INSTANCE_ID
```

**Destroy** (stops all charges, deletes all data):

```bash
vastai destroy instance INSTANCE_ID
```

---

## Option B: Web Console

### 1. Create a template

1. Go to [cloud.vast.ai/templates](https://cloud.vast.ai/templates/)
2. Click **+ New** to create a template from scratch
3. Set the following:

| Field | Value |
|-------|-------|
| **Template Name** | `sdcpp-flux-klein-9b` |
| **Image Path:Tag** | `ghcr.io/philipsorst/sdcpp-flux-klein-9b.docker:latest` |
| **Launch Mode** | `docker ENTRYPOINT` |
| **Disk** | 40 GB |
| **Ports** | `1234` |
| **Environment variables** | `HF_TOKEN=hf_your_token_here`, `OPEN_BUTTON_PORT=1234` |

> **Important:** Select the **docker ENTRYPOINT** launch mode. Do NOT choose
> SSH or Jupyter — those modes override the image entrypoint and would
> prevent the model download and server startup from running.

4. Click **Create**

### 2. Rent an instance

1. Click **Create & Use** (or find the template later under "My Templates")
2. You'll be taken to the offers search page with the template pre-selected
3. Filter by GPU type, VRAM, and price
4. Click **Rent** on a suitable offer
5. Wait for the instance status to reach `running`
6. Monitor model download in the instance logs

### 3. Access the server

Click the **Open** button on the instance card (mapped to port 1234 via
`OPEN_BUTTON_PORT`), or use the **IP Port Info** popup to find the
`PUBLIC_IP:EXTERNAL_PORT` for port 1234.

---

## Cost Optimization

| Strategy | Savings | Trade-off |
|----------|---------|-----------|
| **Interruptible instances** | Up to 50–70% | Can be terminated at any time |
| **Reserved instances** | Up to 50% | Must pre-pay for a duration |
| **Stop instead of destroy** | Pauses GPU billing | Disk charges continue (~$0.05–0.15/GB/month) |
| **Reuse a volume** | Skip re-download on new instance | Requires a persistent volume (see below) |

### Persistent model volume

To avoid re-downloading ~15 GB of models every time you create a new instance,
use a Vast.ai volume:

1. Create a volume:

```bash
vastai create volume --size 20 --label models
```

2. Find the volume ID:

```bash
vastai show volumes
```

3. Link the volume when creating an instance, and set `MODEL_DIR` to the
   mount path:

```bash
vastai create instance OFFER_ID \
  --image ghcr.io/philipsorst/sdcpp-flux-klein-9b.docker:latest \
  --disk 10 \
  --link-volume VOLUME_ID \
  --mount-path /models \
  --env '-e HF_TOKEN=hf_your_token_here -e MODEL_DIR=/models -e OPEN_BUTTON_PORT=1234 -p 1234:1234' \
  --onstart-cmd '/entrypoint.sh'
```

The entrypoint checks for existing files and skips downloads that are already
complete. On subsequent instances with the same volume, startup is nearly
instant.

---

## Passing extra sd-server flags

The entrypoint passes all extra arguments (`"$@"`) to `/sd-server`. You can
override defaults like `--steps` or `--cfg-scale` by appending them after the
entrypoint. With the CLI, use `--args`:

```bash
vastai create instance OFFER_ID \
  --image ghcr.io/philipsorst/sdcpp-flux-klein-9b.docker:latest \
  --disk 40 \
  --env '-e HF_TOKEN=hf_your_token_here -p 1234:1234' \
  --entrypoint /entrypoint.sh \
  --args --steps 20 --cfg-scale 1.0
```

Available flags:

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

---

## Troubleshooting

### Instance immediately exits

Check the logs:

```bash
vastai logs INSTANCE_ID
```

Common causes:

- **Missing `HF_TOKEN`** – the entrypoint exits immediately if `HF_TOKEN` is
  not set. Make sure you pass `-e HF_TOKEN=...` in `--env`.
- **Entrypoint not running** – ensure you're using Entrypoint launch mode (no
  `--ssh` or `--jupyter` flags). SSH/Jupyter modes replace the image
  entrypoint. If you need SSH, use `--onstart-cmd '/entrypoint.sh'` to invoke
  the entrypoint from the onstart script.

### Model download fails

The entrypoint retries up to `MAX_ATTEMPTS` (default 3) times. If it still
fails, check:

- The `HF_TOKEN` is valid and has accepted the FLUX.2-dev license.
- The host has sufficient download bandwidth. Check `inet_down` in the offer
  search results.

Increase retry attempts:

```bash
--env '-e HF_TOKEN=... -e MAX_ATTEMPTS=10 -p 1234:1234'
```

### Out of VRAM (OOM)

The entrypoint already passes `--offload-to-cpu`, which spills to system
RAM. If you still see OOM errors:

- Choose a GPU with more VRAM (>= 16 GB recommended).
- Ensure the host has enough system RAM (>= 32 GB).

### Port not accessible

Vast.ai assigns random external ports. Always check the **IP Port Info**
popup or `vastai show instance` output. The internal port is 1234; the
external port will be different.

---

## Reference

- [Vast.ai Documentation](https://docs.vast.ai)
- [Vast.ai CLI Reference](https://docs.vast.ai/cli/hello-world)
- [Vast.ai Instance Search](https://cloud.vast.ai/create/)
- [stable-diffusion.cpp Docker docs](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/docker.md)
- [stable-diffusion.cpp FLUX.2 guide](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/flux2.md)
- [FLUX.2-klein-9B model card](https://huggingface.co/black-forest-labs/FLUX.2-klein-9B)

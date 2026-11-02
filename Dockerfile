ARG CUDA_VERSION=12.8.2
ARG UBUNTU_VERSION=24.04

# =============================================================================
# Build stage: compile stable-diffusion.cpp from source
# =============================================================================
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git cmake ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /sd.cpp

# Upstream source. SDCPP_REF may be a branch (default: master), tag, or commit SHA.
# CI resolves master to a SHA and passes it here so builds are reproducible and
# Docker layer caching invalidates when upstream moves.
ARG SDCPP_REF=master
RUN git clone https://github.com/leejet/stable-diffusion.cpp.git . && \
    git checkout "${SDCPP_REF}" && \
    git submodule update --init --recursive

ARG CUDACXX=/usr/local/cuda/bin/nvcc
# CUDA architectures to compile kernels for. Includes sm_120 (Blackwell) so
# SageAttention works on RTX 5090-class GPUs (requires CUDA 12.8+ and SM80+).
ARG CUDA_ARCHITECTURES="75;80;86;89;90;100;120"

# Flag set mirrors upstream docker/Dockerfile.cuda with
# GGML_CUDA_ENABLE_DYNAMIC_CPU_BACKENDS=ON: shared libs, dynamic backend
# loading, and several CPU kernel variants with runtime autoselection
# (GGML_NATIVE=OFF so kernels are not tied to the build machine's CPU).
# SD_SERVER_BUILD_FRONTEND=OFF: no web UI, API-only server (no Node/pnpm needed).
RUN cmake . -B ./build \
        -DSD_CUDA=ON \
        -DSD_BUILD_SHARED_LIBS=ON \
        -DGGML_NATIVE=OFF \
        -DSD_BUILD_SHARED_GGML_LIB=ON \
        -DGGML_BACKEND_DL=ON \
        -DGGML_CPU_ALL_VARIANTS=ON \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
        '-DCMAKE_INSTALL_RPATH=$ORIGIN' \
        "-DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES}" \
        -DSD_SERVER_BUILD_FRONTEND=OFF
RUN cmake --build ./build --config Release -j$(nproc)

# =============================================================================
# Runtime stage
# =============================================================================
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

ENV UV_INSTALL_DIR=/usr/local/bin \
    UV_TOOL_BIN_DIR=/usr/local/bin

RUN apt-get update && \
    apt-get install -y --no-install-recommends aria2 ca-certificates curl libgomp1 && \
    curl -LsSf https://astral.sh/uv/install.sh | sh && \
    rm -rf /var/lib/apt/lists/* && \
    uv tool install huggingface_hub && \
    uv cache clean

# Vast.ai installs openssh-server in its overlay and sets StrictModes no via sed,
# but Ubuntu 24.04 ships "#StrictModes yes" (commented) so the sed is a no-op and
# StrictModes defaults to yes, causing "bad ownership or modes for authorized_keys".
# This drop-in is loaded via the Include directive in sshd_config and survives
# the openssh-server install in vast.ai's overlay.
RUN mkdir -p /etc/ssh/sshd_config.d && \
    echo 'StrictModes no' > /etc/ssh/sshd_config.d/99-strictmodes-no.conf && \
    mkdir -p /root/.ssh && chmod 700 /root/.ssh

RUN mkdir -p /loras

COPY --from=build /sd.cpp/build/bin /sd.cpp/bin
RUN printf '#!/bin/sh\nexec /sd.cpp/bin/sd-cli "$@"\n' > /sd-cli && \
    printf '#!/bin/sh\nexec /sd.cpp/bin/sd-server "$@"\n' > /sd-server && \
    chmod +x /sd-cli /sd-server

WORKDIR /sd.cpp

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=1800s --retries=3 \
    CMD curl --fail http://localhost:${PORT:-1234}/sdcpp/v1/capabilities || exit 1

ENTRYPOINT ["/entrypoint.sh"]

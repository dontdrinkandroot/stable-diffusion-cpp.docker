FROM ghcr.io/leejet/stable-diffusion.cpp:master-cuda

ENV UV_INSTALL_DIR=/usr/local/bin \
    UV_TOOL_BIN_DIR=/usr/local/bin

RUN apt-get update && \
    apt-get install -y --no-install-recommends aria2 ca-certificates curl && \
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

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=1800s --retries=3 \
    CMD curl --fail http://localhost:${PORT:-1234}/sdcpp/v1/capabilities || exit 1

ENTRYPOINT ["/entrypoint.sh"]

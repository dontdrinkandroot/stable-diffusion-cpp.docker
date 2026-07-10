FROM ghcr.io/leejet/stable-diffusion.cpp:master-cuda

RUN apt-get update && \
    apt-get install -y --no-install-recommends aria2 ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /loras

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=1800s --retries=3 \
    CMD curl --fail http://localhost:${PORT:-1234}/sdcpp/v1/capabilities || exit 1

ENTRYPOINT ["/entrypoint.sh"]

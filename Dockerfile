FROM ghcr.io/leejet/stable-diffusion.cpp:master-cuda

RUN apt-get update && \
    apt-get install -y --no-install-recommends aria2 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

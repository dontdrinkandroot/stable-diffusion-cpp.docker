FROM ghcr.io/leejet/stable-diffusion.cpp:master-cuda

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates unzip && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/rclone.zip https://downloads.rclone.org/rclone-current-linux-amd64.zip && \
    unzip -q /tmp/rclone.zip -d /tmp/rclone && \
    cp /tmp/rclone/rclone-*-linux-amd64/rclone /usr/bin/rclone && \
    chmod 755 /usr/bin/rclone && \
    rm -rf /tmp/rclone /tmp/rclone.zip

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        iptables \
        iproute2 \
        procps \
        sudo \
        nano \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

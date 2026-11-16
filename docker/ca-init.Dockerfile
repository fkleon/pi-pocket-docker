FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates openssl util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY ca-init.sh /usr/local/bin/ca-init
ENTRYPOINT ["/bin/sh", "/usr/local/bin/ca-init"]

FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates openssl util-linux \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 10003 user \
    && useradd --uid 10003 --gid user --home-dir /home/user --no-create-home --shell /bin/sh user \
    && mkdir -p /home/user /ca-private /ca-public \
    && touch /ca-private/.ca-volume-init /ca-public/.ca-volume-init \
    && chown -R user:user /home/user /ca-private /ca-public \
    && chmod 700 /home/user /ca-private \
    && chmod 755 /ca-public

COPY ca-init.sh /usr/local/bin/ca-init
ENV HOME=/home/user
USER user:user
ENTRYPOINT ["/bin/sh", "/usr/local/bin/ca-init"]

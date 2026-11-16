FROM chromedp/headless-shell:latest

USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates libnss3-tools \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/home/user
RUN mkdir -p $HOME/.local/share/pki/nssdb $HOME/chrome \
    && chown -R 65534:65534 $HOME

COPY chrome-entrypoint.sh /usr/local/bin/chrome-entrypoint
ENTRYPOINT ["/bin/sh", "/usr/local/bin/chrome-entrypoint"]

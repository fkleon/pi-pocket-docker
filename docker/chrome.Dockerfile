FROM chromedp/headless-shell:latest

USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY iron-proxy-ca.crt /usr/local/share/ca-certificates/iron-proxy.crt
RUN update-ca-certificates

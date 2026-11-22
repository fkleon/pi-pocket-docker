FROM chromedp/headless-shell:latest

ARG APP_UID=10002
ARG APP_GID=10002

USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates libnss3-tools \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid ${APP_GID} user \
    && useradd --uid ${APP_UID} --gid ${APP_GID} --home-dir /home/user --no-create-home --shell /bin/sh user \
    && mkdir -p /home/user/.local/share/pki/nssdb /home/user/chrome \
    && touch /home/user/.local/share/pki/nssdb/.nss-volume-init \
    && chown -R user:user /home/user \
    && chmod 700 /home/user
ENV HOME=/home/user
USER user:user

COPY chrome-entrypoint.sh /usr/local/bin/chrome-entrypoint
ENTRYPOINT ["/bin/sh", "/usr/local/bin/chrome-entrypoint"]

# Interactive Pi CLI image, sharing Pi Pocket's configuration volume.
FROM debian:trixie-slim

ARG APP_UID=10001
ARG APP_GID=10001
ARG VERSION=1.4.0
ARG CHECKSUM=sha256:f2e4e4329603223d03260cdb8bd5033dbdc1f73ba58ab8939db2e56546e115d2

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dnsutils \
        fd-find \
        git \
        ripgrep && \
    ln -s /bin/fdfind /bin/fd && \
    rm -rf /var/lib/apt/lists/*

ADD --checksum=${CHECKSUM} \
    https://github.com/earendil-works/pi/releases/download/v${VERSION}/pi-linux-x64.tar.gz \
    /tmp/pi-linux-x64.tar.gz

RUN mkdir /opt/pi-coding-agent && \
    tar xf /tmp/pi-linux-x64.tar.gz -C /opt/pi-coding-agent/ --strip-components=1 && \
    ln -s /opt/pi-coding-agent/pi /usr/bin/pi && \
    rm /tmp/pi-linux-x64.tar.gz && \
    test "$APP_UID" -gt 0 && test "$APP_GID" -gt 0 && \
    groupadd --gid "$APP_GID" user && \
    useradd --uid "$APP_UID" --gid user --home-dir /home/user --no-create-home --shell /bin/bash user && \
    mkdir -p /home/user/.pi /workspace && \
    chown -R user:user /home/user /workspace && \
    chmod 700 /home/user && chmod 2770 /workspace

USER user:user

# Pi Agent: config and extensions (local)
COPY --chown=user:user pi/agent/ /home/user/.pi/agent/

# Pi Agent: extensions (remote)
ADD \
  --checksum=sha256:5e71eddef1e04c104d41fe23d969d8b22f69794f5999d2e46f548260a0211506 \
  --chown=user:user \
  https://raw.githubusercontent.com/mitsuhiko/agent-stuff/refs/tags/1.6.0/extensions/whimsical.ts \
  /home/user/.pi/agent/extensions/

VOLUME "/home/user/.pi"
VOLUME "/workspace"

ENV HOME=/home/user \
    PI_OFFLINE=1 \
    PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0

WORKDIR /workspace
ENTRYPOINT ["/usr/bin/pi"]
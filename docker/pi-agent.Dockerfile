# Interactive Pi CLI image, sharing Pi Pocket's configuration volume.
FROM debian:trixie-slim

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
    groupadd --system --gid 65532 nonroot && \
    useradd --system --uid 65532 --gid nonroot --no-create-home nonroot && \
    mkdir -p /home/nonroot/.pi /workspace && \
    chown -R nonroot:nonroot /home/nonroot /workspace

USER 65532:65532
RUN ["mkdir", "--parents", "/home/nonroot/.pi"]

# Pi Agent: config and extensions (local)
COPY --chown=65532:65532 pi/agent/ /home/nonroot/.pi/agent/

# Pi Agent: extensions (remote)
ADD \
  --checksum=sha256:5e71eddef1e04c104d41fe23d969d8b22f69794f5999d2e46f548260a0211506 \
  --chown=65532:65532 \
  https://raw.githubusercontent.com/mitsuhiko/agent-stuff/refs/tags/1.6.0/extensions/whimsical.ts \
  /home/nonroot/.pi/agent/extensions/

VOLUME "/home/nonroot/.pi"
VOLUME "/workspace"

ENV HOME=/home/nonroot \
    PI_OFFLINE=1 \
    PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0

WORKDIR /workspace
ENTRYPOINT ["/usr/bin/pi"]

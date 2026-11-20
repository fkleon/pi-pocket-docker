ARG NODE_VERSION=24
FROM node:${NODE_VERSION}-trixie-slim AS node

FROM debian:trixie-slim AS pi-pocket

ARG APP_UID=10001
ARG APP_GID=10001

COPY --from=node /usr/local/bin /usr/local/bin
COPY --from=node /usr/local/lib /usr/local/lib

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
      ripgrep fd-find libatomic1 \
    && ln -s /bin/fdfind /bin/fd \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production

WORKDIR /app
COPY src/pi-pocket/package.json src/pi-pocket/package-lock.json /app
RUN npm ci --omit=dev

#COPY src/pi-pocket/ /app
COPY --parents \
  ./src/pi-pocket/./bin/ \
  ./src/pi-pocket/./docs/ \
  ./src/pi-pocket/./src/ \
  ./src/pi-pocket/./types/ \
  ./src/pi-pocket/./web/ \
  /app/

EXPOSE 8787
WORKDIR /workspace

RUN test "$APP_UID" -gt 0 && test "$APP_GID" -gt 0 \
 && groupadd --gid "$APP_GID" user \
 && useradd --uid "$APP_UID" --gid user --home-dir /home/user --no-create-home --shell /bin/bash user \
 && mkdir -p /home/user/.pi /home/user/.pi-pocket /workspace \
 && chown -R user:user /home/user /workspace \
 && chmod 700 /home/user \
 && chmod 2770 /workspace

COPY docker/app-entrypoint.sh /usr/local/bin/app-entrypoint
ENV HOME=/home/user
USER user:user

# Pi Agent: config and extensions (local)
COPY \
  --chown=user:user \
  ./docker/pi/agent /home/user/.pi/agent

# Pi Agent: extensions (remote)
ADD \
  --checksum=sha256:5e71eddef1e04c104d41fe23d969d8b22f69794f5999d2e46f548260a0211506 \
  --chown=user:user \
  https://raw.githubusercontent.com/mitsuhiko/agent-stuff/refs/tags/1.6.0/extensions/whimsical.ts \
  /home/user/.pi/agent/extensions/

# Pi Pocket: config and MCP extension (local)
COPY \
  --chown=user:user \
  ./docker/pi-pocket/config.json /home/user/.pi-pocket/config.json

COPY \
  --chown=user:user \
  ./src/pocket-mcp/mcp.ts /home/user/.pi-pocket/extensions/mcp.ts

COPY \
  --chown=user:user \
  ./src/pocket-mcp/mcp /home/user/.pi-pocket/extensions/mcp

VOLUME "/home/user/.pi"
VOLUME "/home/user/.pi-pocket"
VOLUME "/workspace"

ENV NPM_CONFIG_UPDATE_NOTIFIER=false \
    PI_SKIP_VERSION_CHECK=1 \
    PI_OFFLINE=1 \
    PI_TELEMETRY=0

ENTRYPOINT ["/bin/sh", "/usr/local/bin/app-entrypoint"]
CMD ["--access", "lan", "--cwd", "/workspace"]

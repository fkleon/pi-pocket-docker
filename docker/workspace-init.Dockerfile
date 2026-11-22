FROM debian:trixie-slim

ARG APP_UID=10001
ARG APP_GID=10001
ENV APP_UID=$APP_UID
ENV APP_GID=$APP_GID

ENTRYPOINT ["/bin/sh", "-ec"]
CMD ["chown -R $APP_UID:$APP_GID /workspace && chmod 2770 /workspace"]

FROM debian:trixie-slim

ARG APP_UID=10001
ARG APP_GID=10001
RUN test "$APP_UID" -gt 0 && test "$APP_GID" -gt 0 \
    && groupadd --gid "$APP_GID" user \
    && useradd --uid "$APP_UID" --gid user --home-dir /home/user --no-create-home --shell /bin/sh user \
    && mkdir -p /home/user /workspace \
    && touch /workspace/.pi-pocket-volume-init \
    && chown -R user:user /home/user /workspace \
    && chmod 700 /home/user \
    && chmod 2770 /workspace
ENV HOME=/home/user
USER user:user
VOLUME /workspace
ENTRYPOINT ["/bin/sh", "-ec"]
CMD ["chmod 2770 /workspace && rm -f /workspace/.pi-pocket-volume-init"]

FROM debian:trixie-slim

ENTRYPOINT ["/bin/sh", "-ec"]
CMD ["chown -R $(id -u):$(id -g) /workspace && chmod 2770 /workspace"]
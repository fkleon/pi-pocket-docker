ARG VERSION=0.59.0
FROM ironsh/iron-proxy:${VERSION}

USER root
RUN addgroup -g 10003 user \
    && adduser -D -H -u 10003 -G user -h /home/user user \
    && mkdir -p /home/user \
    && chown user:user /home/user \
    && chmod 700 /home/user
ENV HOME=/home/user
USER user:user

FROM nginxinc/nginx-unprivileged:alpine

USER root
RUN addgroup -g 10004 user \
    && adduser -D -H -u 10004 -G user -h /home/user user \
    && mkdir -p /home/user \
    && chown user:user /home/user \
    && chmod 700 /home/user
ENV HOME=/home/user
USER user:user

FROM ironsh/iron-proxy:0.56.0@sha256:727da0cc35a6d73ed2913a38d56c4b9b4476c075149492e4fbf75552e83361ff

USER root
RUN addgroup -g 10003 user \
    && adduser -D -H -u 10003 -G user -h /home/user user \
    && mkdir -p /home/user \
    && chown user:user /home/user \
    && chmod 700 /home/user
ENV HOME=/home/user
USER user:user

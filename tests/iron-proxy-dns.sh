#!/bin/sh
# Integration test against an already running Compose stack. It starts the
# optional agent image and performs real HTTPS requests to github.com.
set -eu

docker compose --profile agent run --rm --no-deps --entrypoint /bin/sh agent -eu -c '
  # Runtime DNS must still resolve service names, while the gateway intercepts
  # both allowed and unlisted external names.
  getent ahostsv4 gateway | grep -q "^172[.]28[.]0[.]11 "
  getent ahostsv4 chrome | grep -q "^172[.]28[.]0[.]10 "
  getent ahostsv4 app >/dev/null
  for host in github.com example.com; do
    [ "$(dig +time=2 +tries=1 +short @172.28.0.11 "$host" A)" = 172.28.0.11 ]
    [ "$(dig +time=2 +tries=1 +short @172.28.0.11 "$host" AAAA)" = "" ]
  done
  [ "$(getent ahostsv4 example.com | awk "NR==1 {print \$1}")" = 172.28.0.11 ]

  # Direct HTTPS via DNS interception and explicit HTTPS proxying must work;
  # unlisted direct and explicitly proxied requests must be rejected.
  curl --noproxy "*" --fail --silent --show-error --max-time 30 -o /dev/null https://github.com/
  curl --proxy http://gateway:8888 --fail --silent --show-error --max-time 30 -o /dev/null https://github.com/
  [ "$(curl --noproxy "*" --silent --show-error --max-time 15 -o /dev/null -w "%{http_code}" https://example.com/)" = 403 ]
  [ "$(curl --proxy http://gateway:8888 --silent --show-error --max-time 15 -o /dev/null -w "%{http_code}" http://example.com/)" = 403 ]
  echo "Iron-proxy DNS and egress integration tests passed."
'

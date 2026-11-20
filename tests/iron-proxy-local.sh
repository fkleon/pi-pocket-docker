#!/bin/sh
# Test the deployment config against an iron-proxy v0.56.0 binary, without Docker.
# Set IRON_PROXY_BIN to the verified release binary. Requires dig, curl, OpenSSL,
# and outbound HTTPS access to github.com. Ports default to 28401-28405.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${IRON_PROXY_BIN:?Set IRON_PROXY_BIN to the iron-proxy v0.56.0 binary}"
tmp=$(mktemp -d)
server=
trap 'if [ -n "$server" ]; then kill "$server" 2>/dev/null || :; wait "$server" 2>/dev/null || :; fi; rm -rf "$tmp"' EXIT HUP INT TERM
base=${TEST_PORT_BASE:-28400}
dns=$((base + 1))
http=$((base + 2))
https=$((base + 3))
tunnel=$((base + 4))
metrics=$((base + 5))

openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/ca.key"
openssl req -x509 -new -sha256 -key "$tmp/ca.key" -days 1 -subj /CN=test-ca \
  -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -out "$tmp/ca.crt"
printf '{"TYPESAFE_API_KEY":"test-only"}\n' > "$tmp/secret.json"
awk -v secret="$tmp/secret.json" '{gsub("/run/secrets/iron-proxy", secret); print}' \
  "$repo/docker/iron-proxy.yaml" > "$tmp/config.yaml"

env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
  IRON_DNS_LISTEN="127.0.0.1:$dns" IRON_DNS_PROXY_IP=127.0.0.1 \
  IRON_PROXY_HTTP_LISTEN="127.0.0.1:$http" IRON_PROXY_HTTPS_LISTEN="127.0.0.1:$https" \
  IRON_PROXY_TUNNEL_LISTEN="127.0.0.1:$tunnel" IRON_METRICS_LISTEN="127.0.0.1:$metrics" \
  IRON_TLS_CA_CERT="$tmp/ca.crt" IRON_TLS_CA_KEY="$tmp/ca.key" \
  "$IRON_PROXY_BIN" -config "$tmp/config.yaml" >"$tmp/proxy.log" 2>&1 &
server=$!
tries=0
until curl --noproxy '*' -fsS "http://127.0.0.1:$metrics/healthz" >/dev/null 2>&1 && \
  [ "$(dig +time=1 +tries=1 +short @127.0.0.1 -p "$dns" healthcheck.invalid A 2>/dev/null)" = 127.0.0.1 ]; do
  tries=$((tries + 1))
  if [ "$tries" -ge 15 ] || ! kill -0 "$server" 2>/dev/null; then
    cat "$tmp/proxy.log" >&2
    echo 'Iron-proxy did not become ready' >&2
    exit 1
  fi
  sleep 1
done

for host in github.com example.com; do
  [ "$(dig +time=2 +tries=1 +short @127.0.0.1 -p "$dns" "$host" A)" = 127.0.0.1 ]
  [ "$(dig +time=2 +tries=1 +short @127.0.0.1 -p "$dns" "$host" AAAA)" = "" ]
done
curl --noproxy '*' --connect-to "github.com:443:127.0.0.1:$https" --cacert "$tmp/ca.crt" \
  --fail --silent --show-error --max-time 30 -o /dev/null https://github.com/
curl --proxy "http://127.0.0.1:$tunnel" --noproxy '' --cacert "$tmp/ca.crt" \
  --fail --silent --show-error --max-time 30 -o /dev/null https://github.com/
[ "$(curl --noproxy '*' --connect-to "example.com:443:127.0.0.1:$https" --cacert "$tmp/ca.crt" \
  --silent --show-error --max-time 15 -o /dev/null -w '%{http_code}' https://example.com/)" = 403 ]
[ "$(curl --proxy "http://127.0.0.1:$tunnel" --noproxy '' --silent --show-error \
  --max-time 15 -o /dev/null -w '%{http_code}' http://example.com/)" = 403 ]
echo 'Iron-proxy DNS and egress local tests passed.'

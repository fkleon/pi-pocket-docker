#!/bin/sh
# Host-side tests for the CA initializer; requires OpenSSL 3 and flock.
set -eu
# Exercise the exact non-root UID used by the initializer and gateway when
# invoked as root, instead of accidentally hiding permission bugs.
if [ "$(id -u)" = 0 ]; then
  command -v setpriv >/dev/null 2>&1 || { echo 'setpriv required when testing as root' >&2; exit 1; }
  exec setpriv --reuid 10003 --regid 10003 --clear-groups \
    --bounding-set=-all --inh-caps=-all --ambient-caps=-all sh "$0" "$@"
fi
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
chmod 755 "$tmp"
export PRIVATE_CA_DIR=$tmp/private PUBLIC_CA_DIR=$tmp/public
run_init() { sh "$repo/docker/ca-init.sh"; }

# Two simultaneous first starts must agree on one persistent CA.
run_init >"$tmp/first.log" 2>&1 &
pid1=$!
run_init >"$tmp/second.log" 2>&1 &
pid2=$!
wait "$pid1" || { cat "$tmp/first.log"; exit 1; }
wait "$pid2" || { cat "$tmp/second.log"; exit 1; }
key_before=$(openssl pkey -in "$PRIVATE_CA_DIR/ca.key" -pubout)
cert_before=$(openssl x509 -in "$PUBLIC_CA_DIR/iron-proxy.pem" -noout -fingerprint -sha256)
bundle_inode=$(ls -i "$PUBLIC_CA_DIR/ca-certificates.crt" | awk '{print $1}')
run_init >/dev/null
[ "$bundle_inode" = "$(ls -i "$PUBLIC_CA_DIR/ca-certificates.crt" | awk '{print $1}')" ]
[ "$key_before" = "$(openssl pkey -in "$PRIVATE_CA_DIR/ca.key" -pubout)" ]
[ "$cert_before" = "$(openssl x509 -in "$PUBLIC_CA_DIR/iron-proxy.pem" -noout -fingerprint -sha256)" ]

# Both the bundle and the hashed directory must validate proxy-signed leaves.
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -subj /CN=localhost -addext 'subjectAltName=DNS:localhost' \
  -keyout "$tmp/leaf.key" -out "$tmp/leaf.csr" >/dev/null 2>&1
openssl x509 -req -in "$tmp/leaf.csr" -CA "$PRIVATE_CA_DIR/ca.crt" \
  -CAkey "$PRIVATE_CA_DIR/ca.key" -set_serial 1 -days 1 -copy_extensions copy \
  -out "$tmp/leaf.crt" >/dev/null 2>&1
openssl verify -CAfile "$PUBLIC_CA_DIR/ca-certificates.crt" "$tmp/leaf.crt" >/dev/null
openssl verify -no-CAfile -no-CAstore -CApath "$PUBLIC_CA_DIR" "$tmp/leaf.crt" >/dev/null
# Missing hash links must be repaired on the next initialization.
proxy_hash=$(openssl x509 -in "$PUBLIC_CA_DIR/iron-proxy.pem" -noout -hash)
rm "$PUBLIC_CA_DIR/$proxy_hash.0"
run_init >/dev/null
openssl verify -no-CAfile -no-CAstore -CApath "$PUBLIC_CA_DIR" "$tmp/leaf.crt" >/dev/null
# Confirm the system bundle is retained, not replaced by the private CA.
cmp -n "$(wc -c < /etc/ssl/certs/ca-certificates.crt)" \
  /etc/ssl/certs/ca-certificates.crt "$PUBLIC_CA_DIR/ca-certificates.crt"

# Exercise real TLS clients when Node and curl are available.
if command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  export TEST_DIR=$tmp
  node -e 'const fs=require("fs"),https=require("https"),p=process.env.TEST_DIR; https.createServer({key:fs.readFileSync(p+"/leaf.key"),cert:fs.readFileSync(p+"/leaf.crt")},(req,res)=>res.end("ok")).listen(0,"127.0.0.1",function(){fs.writeFileSync(p+"/port",String(this.address().port))})' &
  server=$!
  trap 'kill "$server" 2>/dev/null || :; rm -rf "$tmp"' EXIT HUP INT TERM
  attempts=0
  while [ ! -s "$tmp/port" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 50 ] || { echo 'TLS test server failed to start' >&2; exit 1; }
    sleep 0.1
  done
  port=$(cat "$tmp/port")
  CURL_CA_BUNDLE="$PUBLIC_CA_DIR/ca-certificates.crt" curl --fail --silent \
    --noproxy '*' --resolve "localhost:$port:127.0.0.1" "https://localhost:$port/" | grep -q '^ok$'
  NODE_EXTRA_CA_CERTS="$PUBLIC_CA_DIR/iron-proxy.pem" TEST_PORT=$port node -e \
    'require("https").get({host:"localhost",family:4,port:process.env.TEST_PORT},r=>{r.resume();if(r.statusCode!==200)process.exitCode=1}).on("error",e=>{console.error(e);process.exitCode=1})'
  kill "$server"
  wait "$server" 2>/dev/null || :
  trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fi
# The gateway shares the initializer's UID; no other UID can traverse the
# private directory or read the key, even if the volume were mounted.
[ "$(stat -c %u "$PRIVATE_CA_DIR/ca.key")" = "$(id -u)" ]
[ "$(stat -c %a "$PRIVATE_CA_DIR")" = 700 ]
[ "$(stat -c %a "$PRIVATE_CA_DIR/ca.key")" = 600 ]

# Missing or mismatched private material must never cause silent regeneration.
mv "$PRIVATE_CA_DIR/ca.crt" "$tmp/saved.crt"
if run_init >"$tmp/error.log" 2>&1; then echo 'Accepted incomplete pair' >&2; exit 1; fi
mv "$tmp/saved.crt" "$PRIVATE_CA_DIR/ca.crt"
cp "$PRIVATE_CA_DIR/ca.key" "$tmp/saved.key"
openssl ecparam -name prime256v1 -genkey -noout -out "$PRIVATE_CA_DIR/ca.key"
if run_init >"$tmp/error.log" 2>&1; then echo 'Accepted mismatched pair' >&2; exit 1; fi
mv "$tmp/saved.key" "$PRIVATE_CA_DIR/ca.key"
[ "$cert_before" = "$(openssl x509 -in "$PUBLIC_CA_DIR/iron-proxy.pem" -noout -fingerprint -sha256)" ]
echo 'CA initializer tests passed.'

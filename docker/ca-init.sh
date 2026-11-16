#!/bin/sh
set -eu

private=${PRIVATE_CA_DIR:-/ca-private}
public=${PUBLIC_CA_DIR:-/ca-public}
system=${SYSTEM_CERT_DIR:-/etc/ssl/certs}
days=${IRON_PROXY_CA_DAYS:-3650}
subject=${IRON_PROXY_CA_SUBJECT:-/CN=Pi Pocket Iron Proxy CA}

# Serialize concurrent initializers, including separate Compose invocations.
umask 077
mkdir -p "$private" "$public"
exec 9>"$private/.lock"
flock 9
# Only the initializer and the gateway's group can traverse the private volume.
chown 0:65534 "$private"
chmod 750 "$private"
chmod 755 "$public"
key=$private/ca.key
cert=$private/ca.crt
if [ ! -e "$key" ] && [ ! -e "$cert" ]; then
  work=$(mktemp -d "$private/.generate.XXXXXX")
  trap 'rm -rf "$work"' EXIT HUP INT TERM
  openssl ecparam -name prime256v1 -genkey -noout -out "$work/ca.key"
  openssl req -x509 -new -sha256 -key "$work/ca.key" -days "$days" \
    -subj "$subject" -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign' -out "$work/ca.crt"
  # The gateway runs as 65534 with all capabilities dropped.
  chown 0:65534 "$work/ca.key" "$work/ca.crt"
  chmod 640 "$work/ca.key" "$work/ca.crt"
  mv "$work/ca.key" "$key"
  mv "$work/ca.crt" "$cert"
  rm -rf "$work"
  trap - EXIT HUP INT TERM
  echo 'Generated the Iron-proxy CA.'
elif [ ! -f "$key" ] || [ ! -f "$cert" ]; then
  echo 'Incomplete CA pair in the private volume; restore the missing file or rotate the CA.' >&2
  exit 1
fi

# Refuse expired, invalid, or mismatched pairs, rather than silently replacing them.
openssl verify -CAfile "$cert" "$cert" >/dev/null
key_pub=$(openssl pkey -in "$key" -pubout 2>/dev/null)
cert_pub=$(openssl x509 -in "$cert" -pubkey -noout)
if [ "$key_pub" != "$cert_pub" ]; then
  echo 'CA certificate and private key do not match.' >&2
  exit 1
fi

# Build a normal OpenSSL certificate directory, including a combined bundle and
# hashed individual certificates. Clients mount this directory at /etc/ssl/certs.
work=$(mktemp -d "$public/.build.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
chmod 755 "$work"
for file in "$system"/*.pem; do
  [ -f "$file" ] || continue
  cp -L "$file" "$work/$(basename "$file")"
done
cp "$cert" "$work/iron-proxy.pem"
chmod 644 "$work"/*.pem
openssl rehash "$work"
cp "$system/ca-certificates.crt" "$work/ca-certificates.crt"
printf '\n' >> "$work/ca-certificates.crt"
cat "$cert" >> "$work/ca-certificates.crt"
chmod 644 "$work/ca-certificates.crt"
# Do not disrupt existing clients when another Compose invocation starts ca-init.
# Check all files and links, not only the bundle, so an incomplete store is repaired.
same=yes
for file in "$work"/*; do
  destination=$public/$(basename "$file")
  if [ -L "$file" ]; then
    [ -L "$destination" ] && [ "$(readlink "$file")" = "$(readlink "$destination")" ] || same=no
  else
    [ -f "$destination" ] && cmp -s "$file" "$destination" || same=no
  fi
done
work_count=$(find "$work" -maxdepth 1 \( -type f -o -type l \) | wc -l)
public_count=$(find "$public" -maxdepth 1 \( -type f -o -type l \) | wc -l)
[ "$work_count" = "$public_count" ] || same=no
if [ "$same" = no ]; then
  # Services wait for initialization. Stop the stack before changing its roots.
  find "$public" -maxdepth 1 \( -type f -o -type l \) -delete
  cp -a "$work"/. "$public"/
  echo 'Published the system and Iron-proxy CA trust store.'
else
  echo 'System and Iron-proxy CA trust store is unchanged.'
fi
rm -rf "$work"
trap - EXIT HUP INT TERM

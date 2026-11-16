#!/bin/sh
set -eu

# Older Chromium releases prefer an existing legacy NSS database.
if [ -d "$HOME/.pki/nssdb" ]; then
  db=$HOME/.pki/nssdb
else
  db=$HOME/.local/share/pki/nssdb
fi
mkdir -p "$db"
if [ ! -e "$db/cert9.db" ]; then
  certutil -d "sql:$db" -N --empty-password
fi
if certutil -d "sql:$db" -L -n iron-proxy >/dev/null 2>&1; then
  certutil -d "sql:$db" -D -n iron-proxy
fi
certutil -d "sql:$db" -A -t 'C,,' -n iron-proxy -i /etc/ssl/certs/iron-proxy.pem
exec /headless-shell/run.sh "$@"

#!/bin/sh
# Against a running, freshly initialized stack. COMPOSE_ENGINE may be docker
# (default) or podman; the selected engine's Compose provider is used.
set -eu
engine=${COMPOSE_ENGINE:-docker}
compose() { "$engine" compose "$@"; }
check='test "$(id -u)" -ne 0 && test "$HOME" = /home/user &&
  grep -q "^user:.*:/home/user:" /etc/passwd &&
  test "$(awk "/^CapEff:/ {print \$2}" /proc/self/status | tr -d 0)" = ""'
for service in gateway chrome app ingress; do
  compose exec -T "$service" sh -eu -c "$check"
done
compose --profile agent run --rm --no-deps --entrypoint /bin/sh agent -eu -c "$check"
compose run --rm --no-deps --entrypoint /bin/sh ca-init -eu -c "$check"
compose run --rm --no-deps --entrypoint /bin/sh workspace-init -eu -c "$check"

app_uid=$(compose exec -T app id -u | tr -d '\r\n')
app_gid=$(compose exec -T app id -g | tr -d '\r\n')
workspace_uid=$(compose run --rm --no-deps --entrypoint id workspace-init -u | tr -d '\r\n')
[ "$app_uid" = "$workspace_uid" ]
agent_uid=$(compose --profile agent run --rm --no-deps --entrypoint id agent -u | tr -d '\r\n')
agent_gid=$(compose --profile agent run --rm --no-deps --entrypoint id agent -g | tr -d '\r\n')
[ "$app_uid:$app_gid" = "$agent_uid:$agent_gid" ]
gateway_uid=$(compose exec -T gateway id -u | tr -d '\r\n')
ca_uid=$(compose run --rm --no-deps --entrypoint id ca-init -u | tr -d '\r\n')
[ "$gateway_uid" = "$ca_uid" ]
[ "$gateway_uid" != "$app_uid" ]
compose exec -T gateway sh -eu -c 'test -r /run/iron-proxy/ca.key; test -r /run/secrets/iron-proxy'
compose exec -T app sh -eu -c 'test ! -e /run/iron-proxy/ca.key; test ! -e /run/secrets/iron-proxy'
compose exec -T chrome sh -eu -c 'test ! -e /run/iron-proxy/ca.key; test ! -e /run/secrets/iron-proxy; test -w "$HOME/.local/share/pki/nssdb"'

# Test actual workspace group access, including app-created directories/files.
name=.identity-test-$$
trap 'compose exec -T app rm -rf "/workspace/$name" >/dev/null 2>&1 || :' EXIT HUP INT TERM
compose exec -T app sh -eu -c 'umask 002; mkdir "$1"; echo workspace-test > "$1/file"' sh "/workspace/$name"
compose exec -T chrome sh -eu -c 'test -r "$1/file"; test ! -w "$1/file"' sh "/workspace/$name"
compose --profile agent run --rm --no-deps --entrypoint /bin/sh agent -eu -c 'test -w "$1/file"' sh "/workspace/$name"
echo 'Container identity and shared-volume tests passed.'

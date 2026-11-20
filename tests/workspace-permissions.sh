#!/bin/sh
# Host-side permission test; requires root and setpriv. No container engine.
set -eu
[ "$(id -u)" = 0 ] || { echo 'Run as root to simulate multiple container UIDs.' >&2; exit 1; }
command -v setpriv >/dev/null
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
chmod 755 "$work"
mkdir "$work/workspace"
chown 10001:10001 "$work/workspace"
chmod 2770 "$work/workspace"
setpriv --reuid=10001 --regid=10001 --clear-groups --bounding-set=-all \
  sh -c 'umask 002; mkdir "$1/dir"; printf data > "$1/dir/file"' sh "$work/workspace"
setpriv --reuid=10002 --regid=10002 --groups=10001 --bounding-set=-all \
  test -r "$work/workspace/dir/file"
if setpriv --reuid=10002 --regid=10002 --clear-groups --bounding-set=-all \
  test -r "$work/workspace/dir/file"; then
  echo 'Workspace unexpectedly readable without its supplemental group.' >&2
  exit 1
fi
echo 'Workspace permission tests passed.'

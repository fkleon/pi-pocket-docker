#!/bin/sh
# New workspace files remain readable by the browser’s shared workspace group.
umask 002
exec node /app/bin/pi-pocket.js "$@"

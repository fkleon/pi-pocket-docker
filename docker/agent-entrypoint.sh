#!/bin/sh
# Match the app’s workspace permissions when the CLI creates files.
umask 002
exec /usr/bin/pi "$@"

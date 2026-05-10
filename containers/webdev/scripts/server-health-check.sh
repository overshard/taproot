#!/bin/sh
#
# server-health-check.sh
#
# Run the alpine server's /root/server-health-check.sh from inside webdev,
# streaming its output back. Same script that's printed in the daily MOTD on
# the server itself.
#
# Override the host with $ALPINE_HOST if it's ever something other than
# root@bythewood.me.
#

set -eu

ALPINE_HOST="${ALPINE_HOST:-root@bythewood.me}"

exec ssh "$ALPINE_HOST" /root/server-health-check.sh

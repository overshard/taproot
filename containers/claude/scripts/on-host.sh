#!/bin/sh
#
# on-host.sh
#
# Run a command as root on the VPS host, from inside the claude container:
#
#   on-host systemctl status docker
#   on-host sh -s < script.sh
#
# The Docker socket already makes this container root on the host, and this is
# the one named way to use that. The guard hook still refuses the same flags
# typed anywhere else, so a host change is always an on-host line in the log.
#

set -eu

[ $# -gt 0 ] || { echo "usage: on-host command [args]" >&2; exit 2; }

tty=""
[ -t 0 ] && tty="-t"

exec sudo docker run --rm -i $tty --pid=host --privileged orchard-util \
    nsenter -t 1 -m -u -i -n -p -- "$@"

#!/bin/sh
#
# restic-alert.sh
#
# Push a high priority ntfy alert when a backup or check fails. The host's
# systemd units call it through OnFailure, with the failed unit's name:
#
#   restic-alert restic-backup.service
#
# It borrows status' write token and topic, since the phone already listens
# there and ntfy has no other account that can publish. The post goes over the
# orchard-edge bridge from orchard-util, because Caddy refuses publishes on the
# public hostname.
#

set -u

unit="${1:-a restic job}"
host="unknown host"
[ -r "$HOME/.restic/b2-env" ] && . "$HOME/.restic/b2-env" && host="${RESTIC_HOST:-$host}"

env_file="$HOME/code/orchard/sites/status.bythewood.me/.env"
token=$(sed -n 's/^NTFY_TOKEN=//p' "$env_file" 2>/dev/null)
if [ -z "$token" ]; then
    echo "no NTFY_TOKEN in $env_file, so no alert was sent" >&2
    exit 1
fi

sudo docker run --rm --network orchard-edge orchard-util \
    curl -fsS -o /dev/null \
    -H "Authorization: Bearer $token" \
    -H "Title: Backup failed on $host" \
    -H "Priority: high" \
    -H "Tags: floppy_disk" \
    -d "$unit failed. Look with: journalctl -u $unit" \
    http://orchard-ntfy:8000/status

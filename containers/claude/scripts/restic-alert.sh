#!/bin/sh
#
# restic-alert.sh
#
# Push a high priority ntfy alert when a backup or check fails. The host's
# systemd units call it through OnFailure, with the failed unit's name:
#
#   restic-alert restic-backup.service
#

set -u

unit="${1:-a restic job}"
host="unknown host"
[ -r "$HOME/.restic/b2-env" ] && . "$HOME/.restic/b2-env" && host="${RESTIC_HOST:-$host}"

# The image drops the .sh, a checkout keeps it.
alert="$(dirname "$0")/ntfy-alert"
[ -x "$alert" ] || alert="$alert.sh"

exec "$alert" "Backup failed on $host" "$unit failed. Look with: journalctl -u $unit" high floppy_disk

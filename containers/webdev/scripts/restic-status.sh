#!/bin/sh
#
# restic-status.sh
#
# Show backup health for the webdev restic repo: the latest snapshot for each
# machine that backs up to it, and what it costs in B2.
#
# Files used:
#   ~/.restic/b2-env    B2 account creds (required)
#   ~/.restic/password  repo password (required)
#

set -u

. "$HOME/.restic/b2-env"

REPO="b2:overshard-backups:webdev"
PW_FILE="$HOME/.restic/password"

export RESTIC_REPOSITORY="$REPO"
export RESTIC_PASSWORD_FILE="$PW_FILE"

# b2-env exports RESTIC_HOST for restic-backup's --host tag, but restic also
# honours it as the --host filter on read commands, so leaving it set quietly
# limits every query below to the machine running this script.
unset RESTIC_HOST

echo "Now: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo ""
echo "=== webdev ($REPO) ==="

if [ ! -s "$PW_FILE" ]; then
    echo "  password file missing or empty: $PW_FILE"
    echo "  (place the repo password there, chmod 600)"
    exit 1
fi

if ! restic cat config >/dev/null 2>&1; then
    echo "  cannot open repository (check creds / network)"
    exit 1
fi

echo ""
echo "  Latest snapshot per host:"
restic snapshots --latest 1 --group-by host --compact 2>/dev/null \
    | sed 's/^/    /'

echo ""
echo "  Repo size:"
restic stats --mode raw-data 2>/dev/null \
    | grep -E 'Total (Size|Blob Count|Uncompressed Size)|Compression Ratio' \
    | sed 's/^[[:space:]]*/    /'
echo ""

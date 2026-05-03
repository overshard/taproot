#!/bin/sh
#
# status.sh
#
# Show backup health for both restic repos (webdev and alpine) from a single
# command. Both repos live in the same Backblaze B2 account, so the B2 creds
# in ~/.restic/b2-env work for both; only the per-repo password file differs.
#
# Files used:
#   ~/.restic/b2-env           B2 account creds (required)
#   ~/.restic/password         webdev repo password (required)
#   ~/.restic/alpine-password  alpine repo password (optional; warns if missing)
#

set -u

. "$HOME/.restic/b2-env"

# Strip RESTIC_REPOSITORY/RESTIC_PASSWORD_FILE from any inherited env so we
# can set them per-repo below.
unset RESTIC_REPOSITORY
unset RESTIC_PASSWORD_FILE

NOW=$(date -u +'%Y-%m-%d %H:%M:%S UTC')
echo "Now: $NOW"
echo ""

show_repo() {
    label=$1
    repo=$2
    pwfile=$3

    echo "=== $label ($repo) ==="

    if [ ! -s "$pwfile" ]; then
        echo "  password file missing or empty: $pwfile"
        echo "  (place the repo password there, chmod 600)"
        echo ""
        return
    fi

    export RESTIC_REPOSITORY="$repo"
    export RESTIC_PASSWORD_FILE="$pwfile"

    if ! restic cat config >/dev/null 2>&1; then
        echo "  cannot open repository (check creds / network)"
        echo ""
        return
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
}

show_repo "webdev" "b2:overshard-backups:webdev" "$HOME/.restic/password"
show_repo "alpine" "b2:overshard-backups:alpine" "$HOME/.restic/alpine-password"

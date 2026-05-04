#!/bin/sh
#
# backup.sh
#
# Run manually to back up this container to Backblaze B2 via restic.
# Initializes the repo on first run. Prunes per the retention policy
# (7 daily, 4 weekly, 6 monthly) after each successful backup.
#
# Snapshots are tagged with --host so desktop and laptop snapshots stay
# distinct in the shared repo. Retention is applied per (host, paths),
# so each machine gets its own 7d/4w/6m window.
#
# Credentials live in ~/.restic/ (mounted from the bythewood-restic volume):
#   ~/.restic/password   restic repo password (0600)
#   ~/.restic/b2-env     exports B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_HOST (0600)
#
# b2-env example:
#   export B2_ACCOUNT_ID="..."
#   export B2_ACCOUNT_KEY="..."
#   export RESTIC_HOST="desktop"   # or "laptop"
#

set -eu

. "$HOME/.restic/b2-env"
export RESTIC_REPOSITORY="b2:overshard-backups:webdev"
export RESTIC_PASSWORD_FILE="$HOME/.restic/password"

if [ -z "${RESTIC_HOST:-}" ]; then
    echo "ERROR: RESTIC_HOST is not set." >&2
    echo "Add 'export RESTIC_HOST=desktop' (or laptop) to ~/.restic/b2-env" >&2
    exit 1
fi

if ! restic cat config >/dev/null 2>&1; then
    echo "Repository not initialized. Running restic init..."
    restic init
fi

restic backup \
    --verbose \
    --host="$RESTIC_HOST" \
    --exclude-caches \
    --exclude='host_keys' \
    --exclude='node_modules' \
    --exclude='.next' \
    --exclude='.venv' \
    --exclude='__pycache__' \
    --exclude='dist' \
    --exclude='build' \
    --exclude='.cache' \
    --exclude='.vite' \
    --exclude='*.pyc' \
    "$HOME/.claude" \
    "$HOME/code" \
    "$HOME/.ssh"

restic forget --prune \
    --host="$RESTIC_HOST" \
    --keep-daily   7 \
    --keep-weekly  4 \
    --keep-monthly 6

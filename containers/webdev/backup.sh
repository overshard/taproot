#!/bin/sh
#
# backup.sh
#
# Run manually to back up this container to Backblaze B2 via restic.
# Initializes the repo on first run. Prunes per the retention policy
# (7 daily, 4 weekly, 6 monthly) after each successful backup.
#
# Credentials live in ~/.restic/ (mounted from the bythewood-restic volume):
#   ~/.restic/password   restic repo password (0600)
#   ~/.restic/b2-env     exports B2_ACCOUNT_ID and B2_ACCOUNT_KEY (0600)
#

set -eu

. "$HOME/.restic/b2-env"
export RESTIC_REPOSITORY="b2:overshard-backups:webdev"
export RESTIC_PASSWORD_FILE="$HOME/.restic/password"

if ! restic cat config >/dev/null 2>&1; then
    echo "Repository not initialized. Running restic init..."
    restic init
fi

restic backup \
    --verbose \
    --exclude-caches \
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
    --keep-daily   7 \
    --keep-weekly  4 \
    --keep-monthly 6

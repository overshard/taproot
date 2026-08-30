#!/bin/sh
#
# restic-backup.sh
#
# Run manually to back up this container to Backblaze B2 via restic. It
# initializes the repo on first run and prunes to 7 daily, 4 weekly and 6
# monthly after each successful backup.
#
# Snapshots are tagged with --host so desktop and laptop stay distinct in the
# shared repo, and retention applies per host and paths, so each machine keeps
# its own window.
#
# Built code is not backed up. The bare-name excludes match a directory of that
# name at any depth, and cargo's target/ dirs go by --exclude-caches instead,
# since cargo writes a CACHEDIR.TAG into each one. orchard/bin is excluded by
# full path because a bare 'bin' would also drop src/bin trees, which are source.
#
# Credentials live in ~/.restic/, mounted from the bythewood-restic volume, and
# restic-setup is what writes them:
#   ~/.restic/password   restic repo password (0600)
#   ~/.restic/b2-env     exports B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_HOST (0600)
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

# Exit codes are captured rather than left to set -e, since a partial backup
# (restic exit 3) still produced a snapshot the prune has to run against.
backup_exit=0
restic backup \
    --verbose \
    --host="$RESTIC_HOST" \
    --exclude-caches \
    --exclude='node_modules' \
    --exclude='.next' \
    --exclude='.venv' \
    --exclude='__pycache__' \
    --exclude='dist' \
    --exclude='build' \
    --exclude='.cache' \
    --exclude="$HOME/code/orchard/bin" \
    --exclude='.vite' \
    --exclude='*.pyc' \
    "$HOME/.claude" \
    "$HOME/code" \
    "$HOME/.ssh" || backup_exit=$?

prune_exit=0
restic forget --prune \
    --host="$RESTIC_HOST" \
    --keep-daily   7 \
    --keep-weekly  4 \
    --keep-monthly 6 || prune_exit=$?

if [ "$backup_exit" -ne 0 ] || [ "$prune_exit" -ne 0 ]; then
    echo "backup exit ${backup_exit}, prune exit ${prune_exit}" >&2
    exit "$(( backup_exit > prune_exit ? backup_exit : prune_exit ))"
fi

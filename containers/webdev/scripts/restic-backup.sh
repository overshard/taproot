#!/bin/sh
#
# restic-backup.sh
#
# Run manually to back up this container to Backblaze B2 via restic.
# Initializes the repo on first run. Prunes per the retention policy
# (7 daily, 4 weekly, 6 monthly) after each successful backup.
#
# Snapshots are tagged with --host so desktop and laptop snapshots stay
# distinct in the shared repo. Retention is applied per (host, paths),
# so each machine gets its own 7d/4w/6m window.
#
# What is deliberately not backed up: built code. We want what can be rebuilt
# from source, not the output. The bare-name excludes below ('dist', 'build',
# 'node_modules', '.venv') match a directory of that name at any depth, which
# covers orchard's per-site build/ directories. Cargo's target/ dirs are the
# largest thing on disk by far, about 48GB across the seven archived Rust
# projects, and they are skipped by --exclude-caches rather than by name:
# cargo writes a CACHEDIR.TAG into every target/, which is exactly what that
# flag looks for.
#
# orchard/bin is excluded by full path on purpose. A bare --exclude='bin'
# would also drop analytics-rust/src/bin and repos-rust/src/bin, which are
# Rust source, not output.
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

# Capture exit codes instead of letting set -e kill the script: a partial
# backup (restic exit 3, some files unreadable) still produced a snapshot,
# and the retention prune must still run after it.
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

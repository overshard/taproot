#!/bin/sh
#
# restic-backup.sh
#
# Backs up this container to Backblaze B2 via restic. The host's
# restic-backup.timer runs it nightly through docker exec. It
# initializes the repo on first run and prunes to 7 daily, 4 weekly and 6
# monthly after each successful backup.
#
# Snapshots are tagged with --host, which is vps, and retention applies per host,
# so the desktop's old farewell snapshot keeps its own window and isn't pruned.
#
# Built code is not backed up. The bare-name excludes match a directory of that
# name at any depth, and anything with a CACHEDIR.TAG goes by --exclude-caches.
# orchard/bin is excluded by full path because a bare 'bin' would also drop
# src/bin trees, which are source.
# A directory holding a .nobackup file is skipped, for data that stays local.
# Claude Code's background jobs keep scratch under jobs/*/tmp, which has held
# gigabytes of core dumps and copied databases.
#
# On the VPS ~/orchard-backup is a volume, and orchard-dump fills it with a
# consistent copy of orchard's volumes first, so those go to B2 as well.
#
# Credentials live in ~/.restic/, mounted from the claude-restic volume, and
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
    echo "Add 'export RESTIC_HOST=vps' to ~/.restic/b2-env" >&2
    exit 1
fi

# restic retries a capped or refused B2 request quietly instead of failing, so
# every call gets a timeout and the host unit fails and alerts instead of hanging.
# Exit 10 is restic's "repository does not exist", the only case that inits.
config_exit=0
timeout 10m restic cat config >/dev/null 2>&1 || config_exit=$?
if [ "$config_exit" -eq 10 ]; then
    echo "Repository not initialized. Running restic init..."
    restic init
elif [ "$config_exit" -ne 0 ]; then
    echo "ERROR: could not read the repo config (exit $config_exit), is B2 reachable?" >&2
    exit "$config_exit"
fi

dump_exit=0
orchard=""
if [ -d "$HOME/orchard-backup" ]; then
    orchard-dump || dump_exit=$?
    orchard="$HOME/orchard-backup"
fi

# Exit codes are captured rather than left to set -e, since a partial backup
# (restic exit 3) still produced a snapshot the prune has to run against.
backup_exit=0
timeout 3h restic backup \
    --verbose \
    --host="$RESTIC_HOST" \
    --exclude-caches \
    --exclude-if-present=.nobackup \
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
    --exclude='.before-restore-*' \
    --exclude='.tmp' \
    --exclude="$HOME/.claude/jobs/*/tmp" \
    "$HOME/.claude" \
    "$HOME/code" \
    "$HOME/.ssh" $orchard || backup_exit=$?

prune_exit=0
# Repacking downloads packs from B2, so it waits until a tenth of the repo is unused.
timeout 1h restic forget --prune --max-unused 10% \
    --host="$RESTIC_HOST" \
    --keep-daily   7 \
    --keep-weekly  4 \
    --keep-monthly 6 || prune_exit=$?

worst=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
worst=$(( worst > dump_exit ? worst : dump_exit ))
if [ "$worst" -ne 0 ]; then
    echo "dump exit ${dump_exit}, backup exit ${backup_exit}, prune exit ${prune_exit}" >&2
    exit "$worst"
fi

# One record to logging as source backup, whose watchdog pages when a day passes
# without one, so a timer that stopped firing is caught too. Never fails the run.
env_file="$HOME/code/orchard/sites/logging.bythewood.me/.env"
token=$(sed -n 's/^LOGGING_TOKEN=//p' "$env_file" 2>/dev/null || true)
if [ -n "$token" ]; then
    body=$(printf '{"source":"backup","records":[{"t":%s,"l":"INFO","m":"backup finished","a":{"host":"%s"}}]}' \
        "$(date +%s)000" "$RESTIC_HOST")
    # The token goes in on stdin as curl config so it never shows in ps.
    printf 'header = "X-Logging-Token: %s"\n' "$token" |
        sudo docker run --rm -i --network orchard-edge orchard-util \
        curl -fsS -o /dev/null -m 20 -K - -H 'Content-Type: application/json' \
        -d "$body" http://orchard-logging:8000/ingest ||
        echo "backup heartbeat to logging failed" >&2
else
    echo "no LOGGING_TOKEN in $env_file, so no heartbeat was sent" >&2
fi

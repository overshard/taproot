#!/bin/sh
#
# restic-restore.sh
#
# Restore this container from the latest snapshot in Backblaze B2. Existing
# contents of ~/.claude, ~/code, and ~/.ssh are moved aside to
# ~/before-restore-<UTC-ISO>/ first so nothing is lost. All three are volume
# mounts, so it is their contents that move and not the directories.
#

set -eu

. "$HOME/.restic/b2-env"
export RESTIC_REPOSITORY="b2:overshard-backups:webdev"
export RESTIC_PASSWORD_FILE="$HOME/.restic/password"

if [ -z "${RESTIC_HOST:-}" ]; then
    echo "ERROR: RESTIC_HOST is not set in ~/.restic/b2-env" >&2
    exit 1
fi

# Checked before anything is moved aside, so a bad credential or an unreachable
# repo fails here rather than after the working data has been archived.
if ! restic cat config >/dev/null; then
    echo "ERROR: cannot open restic repository $RESTIC_REPOSITORY" >&2
    exit 1
fi

ARCHIVE="$HOME/before-restore-$(date -u +%Y-%m-%dT%H-%M-%SZ)"

echo "Moving existing data aside to $ARCHIVE"
mkdir -p "$ARCHIVE/.claude" "$ARCHIVE/code" "$ARCHIVE/.ssh"

for dir in .claude code .ssh; do
    if [ -d "$HOME/$dir" ]; then
        find "$HOME/$dir" -mindepth 1 -maxdepth 1 \
            -exec mv {} "$ARCHIVE/$dir/" \;
    fi
done

echo "Restoring latest snapshot from $RESTIC_REPOSITORY"
# desktop and laptop share this repo, so a bare `latest` would restore
# whichever machine backed up most recently.
restic restore latest --host="$RESTIC_HOST" --target /

echo ""
echo "Restore complete. Previous data archived at:"
echo "  $ARCHIVE"
echo ""
echo "Once you've verified everything looks right, you can remove the archive:"
echo "  rm -rf $ARCHIVE"

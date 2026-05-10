#!/bin/sh
#
# restic-restore.sh
#
# Restore this container from the latest snapshot in Backblaze B2.
# Existing contents of ~/.claude, ~/code, and ~/.ssh are moved aside to
# ~/before-restore-<UTC-ISO>/ first so nothing is lost.
#
# Note: ~/.claude, ~/code, and ~/.ssh are docker volume mounts, so we move
# their CONTENTS rather than the directories themselves.
#

set -eu

. "$HOME/.restic/b2-env"
export RESTIC_REPOSITORY="b2:overshard-backups:webdev"
export RESTIC_PASSWORD_FILE="$HOME/.restic/password"

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
restic restore latest --target /

echo ""
echo "Restore complete. Previous data archived at:"
echo "  $ARCHIVE"
echo ""
echo "Once you've verified everything looks right, you can remove the archive:"
echo "  rm -rf $ARCHIVE"

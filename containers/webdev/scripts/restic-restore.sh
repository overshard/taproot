#!/bin/sh
#
# restic-restore.sh
#
# Restore this container from the latest snapshot in Backblaze B2. Existing
# contents of ~/.claude, ~/code, and ~/.ssh are moved aside first so nothing is
# lost, each into a .before-restore-<UTC-ISO>/ inside itself. All three are
# volume mounts, so that is a rename within the volume, it cannot run out of
# space, and it survives the container being replaced, which ~/ does not.
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

# A machine that has never backed up has no snapshot under its host, and
# finding that out after moving everything aside leaves it empty.
if [ "$(restic snapshots --host="$RESTIC_HOST" --latest 1 --json)" = "[]" ]; then
    echo "ERROR: no snapshot for host $RESTIC_HOST in $RESTIC_REPOSITORY" >&2
    exit 1
fi

STAMP=".before-restore-$(date -u +%Y-%m-%dT%H-%M-%SZ)"

for dir in .claude code .ssh; do
    if [ -d "$HOME/$dir" ]; then
        echo "Moving existing $HOME/$dir aside to $HOME/$dir/$STAMP"
        mkdir -m 700 "$HOME/$dir/$STAMP"
        # With + rather than \; find exits non-zero when mv does, so set -e
        # stops here before anything is restored over a file that did not move.
        find "$HOME/$dir" -mindepth 1 -maxdepth 1 ! -name "$STAMP" \
            -exec mv -t "$HOME/$dir/$STAMP" {} +
    fi
done

echo "Restoring latest snapshot from $RESTIC_REPOSITORY"
# desktop and laptop share this repo, so a bare `latest` would restore
# whichever machine backed up most recently.
restic restore latest --host="$RESTIC_HOST" --target /

echo ""
echo "Restore complete. Previous data is in:"
for dir in .claude code .ssh; do
    echo "  $HOME/$dir/$STAMP"
done
echo ""
echo "Once you've verified everything looks right, you can remove them:"
echo "  rm -rf $HOME/.claude/$STAMP $HOME/code/$STAMP $HOME/.ssh/$STAMP"

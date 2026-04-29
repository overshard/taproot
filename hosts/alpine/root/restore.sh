#!/bin/sh
#
# restore.sh
#
# Restore /srv from the latest snapshot in Backblaze B2. Existing /srv is
# moved aside to /root/before-restore-<UTC-ISO>/srv/ first so nothing is lost.
#
# Stops docker before moving /srv (running containers bind-mount /srv/docker/*)
# and starts it again after restore completes.
#
# After restore, you'll need to bring projects up manually, e.g.:
#     for d in /srv/docker/*; do (cd "$d" && docker compose up --build -d); done
#

set -eu

. /root/.restic/b2-env
export RESTIC_REPOSITORY="b2:overshard-backups:alpine"
export RESTIC_PASSWORD_FILE="/root/.restic/password"

ARCHIVE="/root/before-restore-$(date -u +%Y-%m-%dT%H-%M-%SZ)"

echo "Stopping docker..."
rc-service docker stop || true

echo "Moving existing /srv aside to $ARCHIVE/srv"
mkdir -p "$ARCHIVE"
if [ -d /srv ]; then
    mv /srv "$ARCHIVE/srv"
fi
mkdir -p /srv

echo "Restoring latest snapshot from $RESTIC_REPOSITORY"
restic restore latest --target /

echo "Starting docker..."
rc-service docker start

echo ""
echo "Restore complete. Previous /srv archived at:"
echo "  $ARCHIVE/srv"
echo ""
echo "Bring projects up with:"
echo "  for d in /srv/docker/*; do (cd \"\$d\" && docker compose up --build -d); done"
echo ""
echo "Once you've verified everything looks right, you can remove the archive:"
echo "  rm -rf $ARCHIVE"

#!/bin/sh
#
# orchard-restore.sh VOLUME [UID]
#
# Put one orchard volume back from ~/orchard-backup, the reverse of
# orchard-dump. Run restic-restore first so ~/orchard-backup holds the snapshot
# you want. VOLUME is a name from ~/orchard-backup, like orchard-blog-data, or
# the short form blog. UID is who owns the files after, 65532 by default since
# every orchard image runs as that.
#
#   orchard-restore analytics
#
# It stops every container using the volume, moves what's in it to
# .before-restore-<UTC>/ inside it, copies the backup in, drops any -wal, -shm
# or -journal so SQLite can't replay a stale log over the restored file, chowns
# it, runs PRAGMA integrity_check on each database and starts the containers
# again, or leaves them stopped if a check fails. The .before-restore copy
# stays until you delete it.
#

set -eu

SRC_VOLUME=claude-orchard-backup
IMAGE=overshard/claude:latest

if [ $# -lt 1 ]; then
    sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

name=$1
owner=${2:-65532}
vol=""
for v in "$name" "orchard-$name-data" "orchard-$name"; do
    if [ -d "$HOME/orchard-backup/$v" ]; then
        vol=$v
        break
    fi
done
if [ -z "$vol" ]; then
    echo "nothing for $name in ~/orchard-backup, run restic-restore first or check the name:" >&2
    ls "$HOME/orchard-backup" >&2
    exit 1
fi

if ! sudo docker volume inspect "$vol" >/dev/null 2>&1; then
    echo "creating volume $vol"
    sudo docker volume create "$vol" >/dev/null
fi

containers=$(sudo docker ps -q --filter "volume=$vol")
if [ -n "$containers" ]; then
    echo "stopping $(sudo docker inspect -f '{{.Name}}' $containers | tr -d / | tr '\n' ' ')"
    # shellcheck disable=SC2086
    sudo docker stop $containers >/dev/null
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
restore_exit=0
sudo docker run --rm -i --pull=never -u 0 --network none \
    -v "$vol:/vol" -v "$SRC_VOLUME:/src:ro" \
    "$IMAGE" sh -s "$vol" "$owner" "$stamp" <<'RESTORE' || restore_exit=$?
set -eu
vol=$1 owner=$2 stamp=$3
old="/vol/.before-restore-$stamp"
mkdir "$old"
find /vol -mindepth 1 -maxdepth 1 ! -name '.before-restore-*' -exec mv {} "$old/" \;
rmdir "$old" 2>/dev/null || echo "kept what was there in .before-restore-$stamp"
rsync -a "/src/$vol/" /vol/
find /vol -path '/vol/.before-restore-*' -prune -o -type f \
    \( -name '*-wal' -o -name '*-shm' -o -name '*-journal' \) -print -exec rm -f {} +
chown -R "$owner:$owner" /vol
bad=0
for f in $(find /vol -path '/vol/.before-restore-*' -prune -o -type f \( -name '*.db' -o -name '*.sqlite3' \) -print); do
    res=$(setpriv --reuid="$owner" --regid="$owner" --clear-groups sqlite3 "$f" 'PRAGMA integrity_check' 2>&1 || true)
    if [ "$res" = ok ]; then
        echo "ok ${f#/vol/}"
    else
        echo "FAILED ${f#/vol/}: $res" >&2
        bad=1
    fi
done
exit "$bad"
RESTORE

# A failed check leaves the site stopped, since starting it on a bad database
# could write over the evidence.
if [ "$restore_exit" -ne 0 ]; then
    echo "restore of $vol failed, so its containers are still stopped." >&2
    [ -z "$containers" ] || echo "Start them with: sudo docker start $(echo $containers)" >&2
    exit "$restore_exit"
fi
if [ -n "$containers" ]; then
    # shellcheck disable=SC2086
    sudo docker start $containers >/dev/null
    echo "started them again"
fi
echo "restored $vol"

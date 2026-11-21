#!/bin/sh
#
# orchard-dump.sh
#
# Copy orchard's volumes into ~/orchard-backup so restic-backup can pick them
# up. restic-backup runs it whenever that directory exists, which is only on
# the VPS, where compose mounts the claude-orchard-backup volume there.
#
# Every orchard-* volume is copied except the ones in SKIP. logging ages out
# anyway and llm-models is model downloads, and both are big enough to matter
# against B2's free 10GB. dns' certificate and ACME key are reissued on their
# own, and its query log is cut from the copy, since a lookup log with client
# addresses shouldn't sit in B2 for six months.
#
# SQLite files go through sqlite3 .backup, since a plain copy of a live
# database and its WAL can catch it half written. Each one is read as its
# owner, so any -shm sqlite3 touches stays owned by the site. Everything else
# is rsynced as is.
#

set -eu

SKIP="orchard-logging-data orchard-llm-models orchard-dns-tls orchard-dns-acme"
OUT_VOLUME=claude-orchard-backup
IMAGE=overshard/claude:latest

mounts=""
names=""
for v in $(sudo docker volume ls -q | grep '^orchard-'); do
    case " $SKIP " in *" $v "*) continue ;; esac
    mounts="$mounts -v $v:/in/$v"
    names="$names $v"
done

if [ -z "$names" ]; then
    echo "no orchard volumes here, nothing to dump"
    exit 0
fi

# The script goes in on stdin, since a bind mount from this container would
# name a path on the host and not in here.
# shellcheck disable=SC2086
sudo docker run --rm -i --pull=never -u 0 --network none $mounts -v "$OUT_VOLUME:/out" \
    "$IMAGE" sh -s $names <<'DUMP'
set -eu
for v in "$@"; do
    mkdir -p "/out/$v"
    rsync -a --delete --exclude='*.db' --exclude='*.sqlite3' \
        --exclude='*-wal' --exclude='*-shm' --exclude='*-journal' "/in/$v/" "/out/$v/"
    find "/in/$v" -type f \( -name '*.db' -o -name '*.sqlite3' \) | while read -r f; do
        dst="/out/$v/${f#/in/$v/}"
        mkdir -p "$(dirname "$dst")"
        setpriv --reuid="$(stat -c %u "$f")" --regid="$(stat -c %g "$f")" --clear-groups \
            sqlite3 "$f" ".backup '/tmp/dump.db'"
        mv /tmp/dump.db "$dst"
        # Not on /tmp/dump.db, since protected_regular stops root opening a
        # file another uid owns in sticky /tmp and sqlite falls back to read only.
        if [ "$v" = orchard-dns-data ]; then
            sqlite3 "$dst" "DELETE FROM queries; VACUUM;"
        fi
    done
done
for d in /out/*; do
    case " $* " in *" ${d#/out/} "*) ;; *) rm -rf "$d" ;; esac
done
chown -R 1001:1001 /out
chmod 700 /out
DUMP
echo "dumped$names"

#!/bin/sh

echo -e "\napk upgrades ------------------------------------------------------------------"
tail /var/log/apk-autoupgrade.log

echo -e "\nrestic backups ----------------------------------------------------------------"
. /root/.restic/b2-env
export RESTIC_REPOSITORY="b2:overshard-backups:alpine"
export RESTIC_PASSWORD_FILE="/root/.restic/password"
# No 2>/dev/null: a credential or network failure must show up in the
# health output, not read as "no snapshots".
restic stats latest | grep -E "Snapshot|Total File Count|Total Size"
restic snapshots --compact | tail -n5

echo -e "\nfree memory  ------------------------------------------------------------------"
free -h | head -n2

echo -e "\nfree space   ------------------------------------------------------------------"
# df on / directly: grepping for /dev/sda shows nothing on hosts whose root
# is vda/nvme/overlay.
df -h /

echo -e "\ncontainer stats ---------------------------------------------------------------"
docker ps -q | xargs docker stats --no-stream

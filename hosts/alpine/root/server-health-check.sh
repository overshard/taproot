#!/bin/sh

echo -e "\napk upgrades ------------------------------------------------------------------"
tail /var/log/apk-autoupgrade.log

echo -e "\nrestic backups ----------------------------------------------------------------"
. /root/.restic/b2-env
export RESTIC_REPOSITORY="b2:overshard-backups:alpine"
export RESTIC_PASSWORD_FILE="/root/.restic/password"
restic stats latest 2>/dev/null | grep -E "Snapshot|Total File Count|Total Size"
restic snapshots --compact 2>/dev/null | tail -n5

echo -e "\nfree memory  ------------------------------------------------------------------"
free -h | head -n2

echo -e "\nfree space   ------------------------------------------------------------------"
df -h | head -n1 && df -h | grep "/dev/sda" | head -n1

echo -e "\ncontainer stats ---------------------------------------------------------------"
docker ps -q | xargs docker stats --no-stream

# Read only sweep of the WSL distro and its Docker engine.
# Run it through the host runner, `host sh -s < scan.sh`.

echo "=== system"
. /etc/os-release && echo "$PRETTY_NAME, kernel $(uname -r)"
uptime
grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo
df -h / /var/lib/docker 2>/dev/null | sort -u
[ -f /var/run/reboot-required ] && echo "reboot required: $(cat /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' ' ')"

echo "=== failed units"
systemctl --failed --no-legend --plain

echo "=== running services"
systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}'

echo "=== enabled unit files"
systemctl list-unit-files --state=enabled --no-legend | awk '{print $1}'

echo "=== timers"
systemctl list-timers --all --no-legend | awk '{print $(NF-1), $NF}'

echo "=== listening sockets"
ss -ltnup | awk 'NR>1 {print $1, $5, $7}'

echo "=== packet filter"
iptables -S INPUT | head -3
iptables -S FORWARD | head -1
ip6tables -S INPUT | head -1
nft list tables

echo "=== apt"
echo "lists last updated: $(stat -c %y "$(ls -t /var/lib/apt/lists/*Release 2>/dev/null | head -1)" 2>/dev/null | cut -d. -f1)"
apt list --upgradable 2>/dev/null | tail -n +2
grep -hE 'Packages that will be upgraded|No packages found|All upgrades installed|ERROR' /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | tail -n 5

echo "=== journal"
journalctl --disk-usage
journalctl -p err -b --no-pager -q | tail -n 20

echo "=== docker"
docker version --format 'engine {{.Server.Version}}, containerd {{range .Server.Components}}{{if eq .Name "containerd"}}{{.Version}}{{end}}{{end}}'
docker info --format 'live-restore={{.LiveRestoreEnabled}} root={{.DockerRootDir}}'
docker ps -a --format '{{.Names}}|{{.Status}}|{{.Ports}}'
docker inspect --format '{{.Name}} restarts={{.RestartCount}}' $(docker ps -q) | grep -v 'restarts=0$'
docker stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}'
docker system df

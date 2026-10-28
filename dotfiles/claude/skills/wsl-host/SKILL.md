---
name: wsl-host
description: Read, update and manage the WSL Debian distro and its Docker engine from the webdev container, using sudo docker and nsenter into the distro. Invoke for scanning systemd units, timers, listeners and packet filter rules, apt updates, checking unattended-upgrades, journal errors, disk and memory, and container health, logs, stats and cleanup. Read only unless the user has said to make the change.
---

# WSL host

webdev talks to the distro's dockerd over the socket, and the socket is root
owned mode 660, so every docker command needs `sudo`. To run something in the
distro itself, outside every container, `host` starts a privileged
`orchard-util` container and enters PID 1's namespaces with nsenter. It runs as
root, so treat it like a root shell on the production box. If the image is
missing, `make util` in orchard builds it.

```sh
~/.claude/skills/wsl-host/host systemctl --failed
~/.claude/skills/wsl-host/host sh -c 'apt list --upgradable 2>/dev/null'
~/.claude/skills/wsl-host/host sh -s < script.sh
```

Plain container work doesn't need `host`, `sudo docker ps`, `logs`, `inspect`,
`stats --no-stream` and `system df` all work from webdev.

## Scanning

`scan.sh` beside this file is a read only sweep and takes a few seconds.

```sh
~/.claude/skills/wsl-host/host sh -s < ~/.claude/skills/wsl-host/scan.sh
```

It covers memory and disk, failed, running and enabled units, timers, listening
sockets, the packet filter policy, apt's upgradable list and the last
unattended-upgrades runs, journal size and errors since boot, and Docker's
version, live-restore, containers, restart counts, memory and disk use. The
container it starts for itself shows up in the list for a second, ignore it.

## Updating

Check `MemAvailable` first and say if it's tight, since the VM is small and a
hang takes the whole desktop with it.

```sh
~/.claude/skills/wsl-host/host sh -c 'apt-get update -q && apt list --upgradable 2>/dev/null'
~/.claude/skills/wsl-host/host sh -c 'DEBIAN_FRONTEND=noninteractive apt-get -y upgrade'
```

Show the user the list before upgrading. unattended-upgrades already takes
security fixes nightly, so this is mostly for everything else. docker-ce and
containerd upgrades restart dockerd, and containers keep running through that only
if `live-restore=true` shows in the scan, otherwise every site restarts, so ask
first. After, check `systemctl --failed`, that every container is back and
healthy, and `/var/run/reboot-required`.

The kernel and WSL itself come from Windows with `wsl --update`, through the
windows-host skill. That and anything needing `wsl --shutdown` stops every
container, so ask first.

## Changing things

Only change the host when the user has said to, and give the undo with each change.

- Units, `systemctl disable --now <unit>` and back with `enable --now`. Check
  `systemctl list-dependencies --reverse <unit>` first.
- Don't write iptables or nft rules by hand. Docker owns those tables and
  rewrites them, and in WSL's NAT mode nothing off the machine reaches the distro
  anyway, so the Windows and Hyper-V firewalls are the boundary. That changes if
  networking is ever switched to mirrored.
- Config goes in `/etc` the Debian way, apt packages, vendor apt repos and
  systemd units, nothing clever, so a person can fix it by hand later.
- `docker builder prune` is safe to suggest. Ask before `docker system prune`,
  `image prune -a` or anything touching volumes, since volumes hold live data.
- Ask before builds, big image pulls, model loads or load tests, and work out the
  RAM against `MemAvailable` first. Don't poll `docker exec` in a tight loop.

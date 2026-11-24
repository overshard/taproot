# When the VPS is gone

This is the way back from a dead or replaced VPS to every site serving again.
Allow something like an hour, most of it waiting on downloads.

## What comes back and what doesn't

GitHub has `orchard` and `taproot`, and the restic repository on B2 has `~/code`
(both checkouts, the memory vault and every site's `.env`), `~/.claude`, `~/.ssh`
and `~/orchard-backup`, which is a copy of orchard's volumes from the night
before. That's everything that matters.

Logging's volume and llm's model weights aren't in it, so logging history starts
fresh. The tunnel credentials come back from Cloudflare and the bare repos on
`repos.bythewood.me` mirror back from GitHub.

## What you need first

None of these are in any backup.

- Bitwarden. The master password and its 2FA recovery code are on the paper in
  the safe.
- Out of Bitwarden, the B2 application key id and key for `overshard-backups`,
  the restic password for the `webdev` repo, and the passphrase for the new
  `/srv`. The restic password is also on the paper, since without it the
  snapshots can't be opened by anyone.
- A Cloudflare login that can see both zones.
- A device with WireGuard and ssh, which `client/setup.sh` gives you.

## 1. The host

A Debian 13 VPS with these, all from apt or Docker's own apt repo and all plain
config in `/etc`:

- sshd with passwords and root login off, WireGuard on 51820/udp as 10.77.0.1,
  and ufw allowing only 51820/udp and everything on wg0. Re-add each client's
  peer and key, `client/setup.sh` prints what it needs. A new VPS has a new
  WireGuard key and address and `client/setup.sh` leaves an existing
  `wg0.conf` alone, so on each client change `PublicKey` and `Endpoint` in
  `/etc/wireguard/wg0.conf` and run `sudo systemctl restart wg-quick@wg0`.
- A LUKS file container mounted at `/srv` with `noauto`, so boot never waits
  on it, and unlocked by hand with `sudo systemctl start srv.mount`. The lines
  that make it are under [The encrypted /srv](#the-encrypted-srv).
- Docker CE with `data-root` on `/srv/docker` and containerd's root on
  `/srv/containerd`, both started by the mount and not at boot. In
  `/etc/docker/daemon.json`, `live-restore`, json-file logs at 3 by 10m, and
  builder GC at `defaultMaxUsedSpace` 3GB and `defaultMinFreeSpace` 8GB.
- zram swap, a journald cap and unattended-upgrades, with
  `"origin=Docker,label=Docker CE";` added to `Origins-Pattern` so Docker
  updates too.
- `X11Forwarding no` and `AllowAgentForwarding no` in
  `/etc/ssh/sshd_config.d/10-hardening.conf`, and
  `/etc/sysctl.d/90-hardening.conf` with `kernel.kptr_restrict = 1`,
  `kernel.yama.ptrace_scope = 1`, `net.core.bpf_jit_harden = 2`,
  `vm.dirty_background_bytes = 33554432` and `vm.dirty_bytes = 134217728`.
- The `DOCKER-USER` block from [firewall.md](firewall.md) at the end of
  `/etc/ufw/after.rules`, since a port Docker publishes skips ufw.
- The `ntfy-alert@.service` and `reboot-required` units from
  [alerts.md](alerts.md).

### The encrypted /srv

The container is one file, `/var/lib/srv.luks`, sized to most of the disk. Make
it once with a passphrase that goes in Bitwarden and on the paper in the safe:

```sh
sudo fallocate -l 60G /var/lib/srv.luks
sudo cryptsetup luksFormat /var/lib/srv.luks
sudo cryptsetup open /var/lib/srv.luks srv
sudo mkfs.ext4 /dev/mapper/srv
sudo cryptsetup close srv
```

Then one line in `/etc/crypttab` and one in `/etc/fstab`. There is no
`srv.mount` file, systemd writes that unit from the fstab line, and `noauto`
on both keeps boot from stopping at a passphrase prompt nobody can answer.

```
# /etc/crypttab
srv /var/lib/srv.luks none luks,noauto

# /etc/fstab
/dev/mapper/srv /srv ext4 noauto,nofail,x-systemd.requires=systemd-cryptsetup@srv.service 0 2
```

Docker and containerd each get a drop-in so they never start on an empty
`/srv`, the same two lines in `/etc/systemd/system/docker.service.d/srv.conf`
and `/etc/systemd/system/containerd.service.d/srv.conf`:

```ini
[Unit]
Requisite=srv.mount
After=srv.mount
```

And the mount pulls them up once it's there, with both disabled at boot:

```sh
sudo systemctl disable docker containerd
sudo mkdir /etc/systemd/system/srv.mount.wants
sudo ln -s /usr/lib/systemd/system/docker.service /etc/systemd/system/srv.mount.wants/
sudo ln -s /usr/lib/systemd/system/containerd.service /etc/systemd/system/srv.mount.wants/
sudo systemctl daemon-reload
```

After that `sudo systemctl start srv.mount` asks for the passphrase, mounts
`/srv` and starts both, which is all `client/unlock-vps` does. Containerd's
root is `root = "/srv/containerd"` in `/etc/containerd/config.toml`.

**NOTE:** the 60G is a guess for a new box. `sudo ls -lh /var/lib/srv.luks` on
the old one says what it was.

## 2. The claude container and the restore

On the host, as root:

```sh
git clone https://github.com/overshard/taproot && cd taproot
docker compose -f containers/claude/compose.yml up -d --build
docker exec -it claude restic-setup
docker exec -it claude restic-restore
docker exec -it claude claude    # then /login
```

`restic-setup` asks for the B2 key, the restic password and the host, which is
`vps`. Check the snapshot date `restic-restore` shows you is the one you expect.
Then write the backup timers from [backups.md](backups.md), but leave them off
until step 4, since a backup that runs while this is half done takes a snapshot
of a half empty tree and that becomes the latest one.

## 3. The sites

Inside the container, put each orchard volume back from `~/orchard-backup/`
first, which creates any volume that isn't there yet:

```sh
for v in $(ls ~/orchard-backup); do orchard-restore "$v"; done
```

Then:

```sh
cd ~/code/orchard && make install
```

It logs into Cloudflare in a browser and recovers the credentials for the
existing `orchard` tunnel, brings every container up, and skips any site that
already has a `.env`, which is right after a restore. `cert.pem` only covers one
Cloudflare zone, so the second zone's hostnames fail the first time. Run it
again and pick the other zone in the browser:

```sh
make tunnel-login
make tunnel
```

If llm's volume didn't come back, the gateway starts with no keys and turns
chat, dash and pond away. `make chat-key dash-key pond-key` hands it back the
keys in their `.env` files, and nothing needs redeploying.

## 4. Finish up

```sh
make doctor                                   # in ~/code/orchard
sudo docker exec claude restic-backup         # from the host
sudo systemctl enable --now restic-backup.timer restic-check.timer
```

## If it stops halfway

`restic-restore` moves whatever is already in each volume into a
`.before-restore-<UTC>/` inside it before it writes, so running it again loses
nothing. And don't run `sh edge/setup-tunnel.sh down` in a hurry, it deletes the
tunnel and leaves every CNAME pointing at nothing.

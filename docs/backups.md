# Backups

The claude container on the VPS backs up to a Backblaze B2 bucket
(`overshard-backups`) using restic. A systemd timer on the host runs it nightly
and a second one reads back 5% of the repo every Sunday. Either one failing
sends a high priority alert to the alerts topic on the phone. Retention is 7
daily, 4 weekly and 6 monthly per host, pruned after each backup. Passwords and
B2 keys live in Bitwarden.

There is one repository, `b2:overshard-backups:webdev`, named for the container
that used to do this job. It holds per-machine snapshots of `~/.claude`, `~/code`
and `~/.ssh`, each tagged with `$RESTIC_HOST`, which is `vps` now. The desktop's
last snapshot is still in there as host `desktop` with its Claude history.

The snapshot also has `~/orchard-backup`, a copy of every orchard volume except
logging and llm-models that `orchard-dump` takes right before. Databases in it
come from `sqlite3 .backup`, so they're consistent even though the sites are
running. To put one back, stop that site, restore the snapshot, and copy its
directory from `orchard-backup/` into the volume.

`restic-setup` is the way in. It reports what is set, verifies it by actually
opening the repository, prompts for anything missing, and writes both files at
`0600`. It also carries the instructions for minting a fresh B2 application key.
From the VPS host:

```sh
sudo docker exec -it claude restic-setup
sudo docker exec claude restic-backup      # take a snapshot now
sudo docker exec claude restic-check       # read back 5% of it
sudo docker exec claude restic-status      # last snapshot per host, and what the repo costs
sudo docker exec -it claude restic-restore # existing data moves to .before-restore-<UTC>/ first
```

**NOTE:** the repo password is not recoverable. Lose it and the snapshots in
that repository are lost with it. It lives in Bitwarden, and on the paper in the safe.

## The host timers

They live on the host and not in the container so rebuilding the container
doesn't lose them, and `Persistent=true` catches up a run the box was down for.
Each is a plain unit in `/etc/systemd/system/`:

```ini
# restic-backup.service
[Unit]
Description=restic backup of the claude volumes
After=docker.service
Requires=docker.service
OnFailure=restic-alert@%n.service

[Service]
Type=oneshot
ExecStart=/usr/bin/docker exec claude restic-backup

# restic-backup.timer
[Unit]
Description=daily restic backup

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target

# restic-alert@.service
[Unit]
Description=phone alert for a failed %i

[Service]
Type=oneshot
ExecStart=/usr/bin/docker exec claude restic-alert %i
```

`restic-check.service` and `restic-check.timer` are the same shape with
`restic-check` and `OnCalendar=Sun 12:00`. After writing them,
`sudo systemctl daemon-reload && sudo systemctl enable --now restic-backup.timer restic-check.timer`,
and `disable --now` on the same two undoes it.

## Helper scripts

These are in `containers/claude/scripts/`, land in `~/scripts/` and are on
`PATH` inside the container:

| Command | What it does |
|---|---|
| `restic-setup`   | Check the B2 credentials, and walk through entering them if they are missing or wrong |
| `restic-backup`  | Run `orchard-dump`, then back up to B2 with the snapshot tagged `$RESTIC_HOST` |
| `restic-check`   | Read back 5% of the repo, run weekly by the host timer |
| `restic-alert`   | Push a phone alert through ntfy, called when either timer fails |
| `orchard-dump`   | Copy orchard's volumes into `~/orchard-backup` |
| `restic-restore` | Pull this host's latest snapshot from B2, existing data archived first |
| `restic-status`  | Last snapshot per host, plus repo size, and `--age` for just this host's |
| `code-sync`      | Pull every repo under `~/code/`, then clone any new ones from GitHub |

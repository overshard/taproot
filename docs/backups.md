# Backups

The webdev container backs up to a Backblaze B2 bucket (`overshard-backups`)
using restic. A systemd timer on the host runs it nightly and a second one
reads back 5% of the repo every Sunday. Either one failing sends a high
priority alert to the status topic on the phone, and `make doctor` says how old
the last snapshot is. Retention is 7 daily, 4 weekly and 6 monthly per host,
pruned after each backup. Passwords and B2 keys live in Bitwarden.

There is one repository, `b2:overshard-backups:webdev`, holding per-machine
snapshots of `~/.claude`, `~/code` and `~/.ssh` from desktop, laptop and vps,
each tagged with `$RESTIC_HOST`.

On the VPS the `claude` container does the same job, and the snapshot also has
`~/orchard-backup`, a copy of every orchard volume except logging and
llm-models that `orchard-dump` takes right before. Databases in it come from
`sqlite3 .backup`, so they're consistent even though the sites are running.
To put one back, stop that site, restore the snapshot, and copy its directory
from `orchard-backup/` into the volume.

The VPS has no make, so its timers are the same three units with
`docker exec claude` in place of `bythewood-webdev`, written by hand.

`make restic` is the way in. It reports what is set, verifies it by actually
opening the repository, prompts for anything missing, and writes both files at
`0600`. It also carries the instructions for minting a fresh B2 application key.

```sh
make backup     # take a snapshot from this machine
make verify     # read back 5% of it
make snapshots  # check the repo from anywhere
make restore    # existing data moves to .before-restore-<UTC>/ inside each volume first
```

**NOTE:** the repo password is not recoverable. Lose it and the snapshots in
that repository are lost with it. It lives in Bitwarden, and on the paper in the safe.

## Helper scripts

The make targets are wrappers around these, which are in `~/scripts/` and on
`PATH` inside the container, so they can be typed directly once you are in
there:

| Command | Target | What it does |
|---|---|---|
| `restic-setup`   | `make restic` | Check the B2 credentials, and walk through entering them if they are missing or wrong |
| `restic-backup`  | `make backup` | Restic backup to B2, run nightly by the host timer, snapshot tagged with `$RESTIC_HOST` |
| `restic-check`   | `make verify` | Read back 5% of the repo, run weekly by the host timer |
| `restic-alert`   | | Push a phone alert through ntfy, called when either timer fails |
| `orchard-dump`   | | Copy orchard's volumes into `~/orchard-backup`, which restic-backup runs on the VPS |
| `restic-restore` | `make restore` | Pull latest snapshot from B2, existing data archived first |
| `restic-status`  | `make snapshots` | Last snapshot per host, plus repo size. `--age` is what doctor uses |
| `code-sync`      | `make sync` | Pull every repo under `~/code/`, then clone any new ones from GitHub |

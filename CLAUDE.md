# CLAUDE.md

taproot is the `claude` container my VPS runs, the thin client setup, my dotfiles and the Claude Code config. Nothing here is a site, and there's no dev server.

## The claude container

It's built from `containers/claude/Dockerfile` by `containers/claude/compose.yml`. Volumes back `code/`, `.claude/`, `.ssh/`, `.restic/` and `orchard-backup/`, and the dev user is UID 1001 to match them, so don't drop the `-u` on the useradd.

There are no make targets for it. Rebuild by building inside it with `sudo docker compose -f containers/claude/compose.yml build` and then running `docker compose up -d` from the host as root, since recreating it from inside kills the shell doing it.

## Host timers

Three systemd timers on the host `docker exec` into the container, and their units live in `/etc/systemd/system/` on the host and not in this repo, see `docs/backups.md` and `docs/vault.md`.

- `restic-backup.timer` runs `restic-backup` nightly, with `orchard-dump` copying orchard's volumes in first.
- `restic-check.timer` reads back a sample weekly.
- `vault-sweep.timer` runs `dotfiles/claude/hooks/vault-sweep.sh` nightly at 05:00 UTC.

## The VPS

It's reached over WireGuard only, `ssh debian@10.77.0.1`, with `MTU = 1220` on both ends since the path from home carries 1280 byte packets. ufw allows 51820/udp and everything on wg0 and nothing else. Docker's data lives on a LUKS `/srv` that has to be unlocked by hand after a reboot with `sudo systemctl start srv.mount`, which starts Docker and everything behind it. `docs/recovery.md` has the rest.

## Thin clients

Desktop WSL, laptop WSL and the phone are thin clients set up by `client/setup.sh`, with WireGuard, ssh and a read-only copy of the vault.

## Claude Code config

`dotfiles/claude/` is symlinked into `~/.claude` except `settings.json`, which is a template since the live one is machine-local. The vault hooks are in `dotfiles/claude/hooks/` and `docs/vault.md` explains them.

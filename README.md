# taproot

Dotfiles, the container I write code in, and the setup for the devices I work
from. That container is `claude` on my VPS, Claude Code driven over remote
control from claude.ai or the app. Nothing is deployed from here, every site I
run lives in [orchard](https://github.com/overshard/orchard).

## Requirements

A Debian host with Docker CE, and WireGuard to reach it, see
[docs/recovery.md](docs/recovery.md) for what the VPS has on it.

## Running it

From a clone, as root on the host:

```sh
docker compose -f containers/claude/compose.yml up -d --build
docker exec -it claude claude    # once, then /login
```

Rebuilding it is the same `--build`, but run from the host and not from inside
the container, since recreating it kills the shell doing it.

Its backups are the restic scripts in `containers/claude/scripts/`, with
`restic-backup.timer` and `restic-check.timer` on the host exec'ing them into the
container, see [docs/backups.md](docs/backups.md). `vault-sweep.timer` on the host
runs the nightly vault job the same way, and Claude Code's hooks write the vault
in between, see [docs/vault.md](docs/vault.md).

Every device I work from (the phone's terminal, WSL on the desktop and laptop)
is the same thin client, set up by `client/setup.sh`. It gives it WireGuard,
a `vps` ssh host, Claude Code, and two scripts: `unlock-vps` for the encrypted
disk after a reboot and `claude-vps` for Claude Code inside the container.

## Layout

```
taproot/
├── client/              setup for a device that works through the VPS
├── docs/                recovery, backups, alerts, the firewall guard and the vault hooks
├── dotfiles/            bash, git, claude
└── containers/claude/   compose file, Dockerfile, scripts copied to ~/scripts/
```

## Things that will bite you

- The mounted `docker.sock` is root-owned mode 660, so docker needs `sudo` in
  the container and the docker group doesn't help.
- Bind mounts of paths under `/home/dev` silently mount an empty directory,
  since the daemon resolves them on the host. Use named volumes.
- Debian's `/etc/profile` assigns `PATH` outright, so a login shell drops what
  `ENV PATH` added. The image carries a `profile.d` snippet for it.
- The repo password for backups can't be recovered, so keep it in Bitwarden
  and on the paper in the safe.
- The `dev` user is UID 1001 to match the volumes, so don't clean up the
  `-u 1001`.
- The gitleaks pre-commit hook is off in a fresh clone. Turn it on with
  `git config core.hooksPath .githooks`, which needs `apt install gitleaks`.

## License

BSD 2-Clause. See [LICENSE.md](LICENSE.md).

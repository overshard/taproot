# Taproot

What holds when the surface turns.

Dotfiles, containers, and the configs that make a machine mine.

## What is this?

The single deep root beneath everything I work on. Personal infrastructure
across every machine I tend, from the development container I write code in
to the Alpine host that runs in the distance.

This is not a framework. It's a living configuration. It grows when something
changes and stays quiet when nothing needs to.

## Structure

```
taproot/
├── dotfiles/                       the soil: bash, git, neovim, tmux
├── containers/
│   ├── webdev/
│   │   ├── Dockerfile              the vessel: Debian 13 dev image
│   │   └── scripts/                copied to ~/scripts/ in the container
│   │       ├── restic-backup.sh        manual restic snapshot to B2
│   │       ├── restic-restore.sh       pull latest snapshot from B2
│   │       ├── restic-status.sh        last snapshot per host across repos
│   │       └── code-sync.sh            pull existing repos + clone new ones from GitHub
│   └── ai/
│       └── Dockerfile              local llama.cpp + pi, loopback only
└── hosts/
    └── alpine/
        ├── quickstart.sh           provision a fresh server
        ├── etc/apk/                package repositories
        ├── etc/periodic/daily/     restic autobackup, apk autoupgrade
        ├── root/                   health check, restore.sh
        └── srv/
            ├── projects.conf       the manifest, every project and repo
            ├── caddy/Caddyfile     the single gate, reverse proxy
            └── bootstrap.sh        clone all repos into a fresh code directory
```

## The projects it tends

Everything deployed lives in `hosts/alpine/srv/projects.conf`, one line per
project: `name|github_repo|branch|has_data_dir|runs_migrations`. The Caddyfile,
post-receive hooks, and bootstrap script all grow from that single file. Every
container listens on 8000 internally; Caddy reaches each one by container name on
the shared `bythewood-edge` network, so there is no per-project port to track.

| Project | What it is |
|---|---|
| [`analytics-rust`](https://github.com/overshard/analytics-rust) | Self-hosted website analytics (Rust axum, SQLite), archived; deployed today |
| [`status-rust`](https://github.com/overshard/status-rust) | Uptime monitor & status page (Rust axum, SQLite), archived; deployed today |
| [`finance-rust`](https://github.com/overshard/finance-rust) | Self-hosted market watcher (Rust axum, SQLite) |
| [`blog.bythewood.me`](https://github.com/overshard/blog.bythewood.me) | Personal blog (Rust axum, markdown files) |
| [`repos-rust`](https://github.com/overshard/repos-rust) | Minimal git repo browser (Rust axum) |
| [`isaacbythewood.com`](https://github.com/overshard/isaacbythewood.com) | Personal portfolio (Next.js) |
| [`timelite`](https://github.com/overshard/timelite) | Local-only time tracker (Next.js) |

## The container

A Debian 13 development workstation with everything already in the ground: Go,
Python (uv), Bun, Claude Code, Docker CLI, typst, neovim, tmux, restic, and
Playwright Chromium (driven by `playwright-cli`, not an MCP). No nodejs and no
npm; Bun runs Playwright, which was the last thing that needed them. No Rust
toolchain either, since every Rust project here is archived. Kept alive with
`sleep infinity`.

Your work lives in four `bythewood-*` volumes rather than in the container, so
the container itself is disposable. Delete it and make a new one whenever you
like; that is the normal way to pick up a new image.

Every command below is a single line on purpose, so it pastes into PowerShell
and sh alike. Run them from a clone of this repo, which is the build context.

### Build and run

```sh
docker build --tag overshard/webdev:latest -f containers/webdev/Dockerfile .
```

Swap a running container for a freshly built image. Volumes are untouched, so
nothing you care about is lost; you do lose the running tmux session:

```sh
docker rm --force bythewood-webdev
docker run --detach --name bythewood-webdev --init --restart unless-stopped --publish 8000:8000 --volume bythewood-code:/home/dev/code --volume bythewood-claude:/home/dev/.claude --volume bythewood-ssh:/home/dev/.ssh --volume bythewood-restic:/home/dev/.restic --volume /var/run/docker.sock:/var/run/docker.sock overshard/webdev:latest
```

Stop and start again without replacing anything:

```sh
docker stop bythewood-webdev
docker start bythewood-webdev
```

Then get in:

```sh
docker exec -it bythewood-webdev tmux
```

### A machine that has never run this before

Needs Docker running and an SSH key at `~/.ssh/home_key` added to GitHub.

Make the four volumes that hold everything, then build and run as above:

```sh
docker volume create bythewood-code
docker volume create bythewood-claude
docker volume create bythewood-ssh
docker volume create bythewood-restic
```

Give it your git key. The 600 matters: ssh refuses anything looser, and a key
copied off Windows arrives with no usable mode.

```sh
docker cp $HOME/.ssh/home_key bythewood-webdev:/home/dev/.ssh/home_key
docker exec bythewood-webdev sh -c "chmod 700 /home/dev/.ssh && chmod 600 /home/dev/.ssh/home_key"
```

Add restic credentials, pasted from 1Password, then pull everything back from
B2. That restore is the only way the memory vault returns, because that repo
has no git remote anywhere:

```sh
docker exec -it bythewood-webdev nvim /home/dev/.restic/password
docker exec -it bythewood-webdev nvim /home/dev/.restic/b2-env
docker exec -it bythewood-webdev restic-restore
```

Finally point Claude Code at the version-controlled skills and status line.
This cannot be baked into the image, because `/home/dev/.claude` is a volume
and shadows whatever the image puts there. Re-run it any time:

```sh
docker exec bythewood-webdev sh -c "ln -snf /home/dev/code/taproot/dotfiles/claude/skills /home/dev/.claude/skills && ln -snf /home/dev/code/taproot/dotfiles/claude/status-line.sh /home/dev/.claude/status-line.sh"
```

### Things that are not obvious

- `--init` is required. Without a real PID 1, tmux leaves zombies behind and
  they accumulate for the life of the container.
- The mounted `docker.sock` is `root:root` mode 660, so docker commands inside
  need `sudo`. Being in the docker group does not help, so there is no docker
  group.
- `--publish` is what makes a dev server on port 8000 reachable from the host
  browser. Publishing a port on some *other* container does not reach this one;
  to curl a neighbour, share its network namespace with `--network container:<name>`.
- Bind mounts of paths under `/home/dev` do not work from inside the container.
  The daemon is Docker Desktop on the Windows host and resolves the source path
  against its own filesystem, where it does not exist, so it silently mounts an
  empty directory instead of failing. Named volumes are what work.

### Helper scripts inside the container

All in `~/scripts/` and on `PATH`:

| Command | What it does |
|---|---|
| `restic-backup`  | Manual restic backup to B2; snapshot tagged with `$RESTIC_HOST` |
| `restic-restore` | Pull latest snapshot from B2; existing data archived first |
| `restic-status`  | Last snapshot per host across both restic repos, plus repo size |
| `code-sync`      | `git fetch && git pull --ff-only` for every repo under `~/code/`, then clones any non-archived non-fork repos owned by overshard on GitHub that aren't local yet |

## The dotfiles

Minimal by intention. I respect defaults and only override what earns it.
Everything in **`dotfiles/`** is baked into the container at build time via
COPY (bash, git, tmux, neovim).

## The host

Alpine Linux. Firewall, daily restic backups to Backblaze B2, and quiet daily
maintenance. The bare repos and post-receive hooks are generated from
`projects.conf` (the Caddyfile is hand-maintained) so the server can be rebuilt
from this repo alone.

Provision a fresh server:

```sh
scp -r hosts/alpine/ root@your-server:/root/alpine
ssh root@your-server "cd /root/alpine && sh quickstart.sh"
```

Bootstrap a fresh code directory with all repos and server remotes:

```sh
cd ~/code
sh taproot/hosts/alpine/srv/bootstrap.sh
```

## Backups

Both the webdev container and the alpine host back up to a single Backblaze B2
bucket (`overshard-backups`) using restic, one repo per kind:

| Repository | What's in it |
|---|---|
| `b2:overshard-backups:webdev` | Per-machine snapshots from desktop and laptop (`~/.claude`, `~/code`, `~/.ssh`). Each snapshot tagged with `$RESTIC_HOST` (`desktop` or `laptop`); retention applies per-machine. |
| `b2:overshard-backups:alpine` | Daily snapshots from the production server (`/srv/git`, `/srv/docker`, `/srv/data`). |

Retention: 7 daily, 4 weekly, 6 monthly per host, pruned after each backup.
Restic passwords and B2 application keys live in 1Password.

### Webdev credentials

Written by hand into the `bythewood-restic` volume, pasted from 1Password (see
the container setup above). The `b2-env` file looks like:

```sh
export B2_ACCOUNT_ID="<keyID>"
export B2_ACCOUNT_KEY="<applicationKey>"
export RESTIC_HOST="desktop"   # or "laptop"
```

Optional: drop the alpine repo password at `~/.restic/alpine-password` so
`restic-status` can report on the alpine repo too. That repository still holds
the old server's backup history even though the server itself is gone.

### Alpine credentials

Placed by hand after `quickstart.sh` runs (the same paste-from-1Password
pattern), at `/root/.restic/password` and `/root/.restic/b2-env`. The alpine
`b2-env` should also have `RESTIC_HOST="alpine"`.

### Daily flow

```sh
restic-backup   # take a snapshot from this machine
restic-status   # check fleet health (both repos, every host) from anywhere
code-sync       # pull every repo under ~/code/ + clone any new ones from GitHub
```

### Restore

Existing data is moved aside to `~/before-restore-<UTC-ISO>/` (webdev) or
`/root/before-restore-<UTC-ISO>/srv/` (alpine) before restic writes the
snapshot back:

```sh
restic-restore                          # webdev (from inside the container)
ssh root@server /root/restore.sh --up   # alpine; --up auto-restarts containers
```

## Philosophy

- Keep defaults until they fail you.
- One repo, one root, everything grows from here.
- If it's not worth tending, remove it.

## License

BSD 2-Clause. See [LICENSE.md](LICENSE.md).

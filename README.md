# Taproot

What holds when the surface turns.

Dotfiles, containers, and the configs that make a machine mine.

## What is this?

The single deep root beneath everything I work on. Personal infrastructure
across every machine I tend — from the development container I write code in
to the Alpine host that runs in the distance.

This is not a framework. It's a living configuration. It grows when something
changes and stays quiet when nothing needs to.

## Structure

```
taproot/
├── dotfiles/                       the soil — bash, git, neovim, tmux
│   └── host/                       host-side configs (Zed, Windows ssh-config)
├── containers/
│   └── webdev/
│       ├── Dockerfile              the vessel — Ubuntu 24.04 dev image
│       ├── bootstrap.ps1           one-shot host setup (Windows)
│       ├── backup.sh, restore.sh   restic to / from B2
│       ├── sync.sh                 git pull every repo under ~/code/
│       └── status.sh               last snapshot per host across repos
└── hosts/
    └── alpine/
        ├── quickstart.sh           provision a fresh server
        ├── etc/caddy/              the single gate — Caddyfile
        ├── etc/docker/             daemon configuration
        ├── etc/periodic/           daily backups and upgrades
        ├── root/                   health checks, restore.sh
        └── srv/
            ├── projects.conf       the manifest — every project, port, repo
            └── bootstrap.sh        clone all repos into a fresh code directory
```

## The projects it tends

Everything deployed lives in `hosts/alpine/srv/projects.conf`. The Caddyfile,
port map, and post-receive hooks all grow from that single file.

| Project | Port | What it is |
|---|---|---|
| [`analytics`](https://github.com/overshard/analytics) | 8000 | Self-hosted website analytics (Django, SQLite) |
| [`blog.bythewood.me`](https://github.com/overshard/blog.bythewood.me) | 8100 | Personal blog (Flask, markdown files) |
| [`timelite`](https://github.com/overshard/timelite) | 8200 | Local-only time tracker (Next.js, IndexedDB) |
| [`isaacbythewood.com`](https://github.com/overshard/isaacbythewood.com) | 8300 | Personal portfolio (Next.js) |
| [`status`](https://github.com/overshard/status) | 8400 | Uptime monitor & status page (Django, SQLite) |
| [`darkfurrow.com`](https://github.com/overshard/darkfurrow.com) | 8500 | Seasonal almanac (Flask) |

## The container

An Ubuntu 24.04 development workstation with everything already in the ground:
Python (uv), Node, Bun, Docker CLI, neovim, tmux, Claude, and Playwright
Chromium (for the Claude playwright MCP). Kept alive with `sleep infinity`.

### Bootstrap on a fresh Windows host

Prereqs: Docker Desktop installed and running, an SSH key at
`$HOME\.ssh\home_key` (and `.pub`) added to GitHub. Nothing else.

```powershell
irm https://raw.githubusercontent.com/overshard/taproot/master/containers/webdev/bootstrap.ps1 -OutFile bootstrap.ps1
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 laptop
```

`-ExecutionPolicy Bypass` is needed because PowerShell blocks scripts pulled
from the internet by default; the flag scopes to that one invocation, no
persistent system change. Use `desktop` or `laptop` as the first arg to tag
this machine's restic snapshots. Re-run any time; every step is idempotent.

Bootstrap creates the four `bythewood-*` volumes, clones taproot into
`bythewood-code` via a throwaway helper container (so the host filesystem stays
clean), builds the image using `docker.sock` and the volume-resident taproot,
runs the container, copies your host SSH key into the volume, and prompts for
restic credentials. Pass `-Force` to pull the latest taproot, rebuild the
image, and recreate the container; pass `-Restore` to also pull data from B2.

Then connect:

```sh
docker exec -it bythewood-webdev tmux       # TUI workflow
ssh -p 2222 dev@localhost                   # editor remote-dev (Zed, VS Code, JetBrains)
```

### Helper scripts inside the container

All in `~/scripts/` and on `PATH`:

| Command | What it does |
|---|---|
| `backup`  | Manual restic backup to B2; snapshot tagged with `$RESTIC_HOST` |
| `restore` | Pull latest snapshot from B2; existing data archived first |
| `sync`    | `git fetch && git pull --ff-only` for every repo under `~/code/` |
| `status`  | Last snapshot per host across both restic repos, plus repo size |

## The dotfiles

Minimal by intention. I respect defaults and only override what earns it.
Two flavors:

- **`dotfiles/`** baked into the container at build time via COPY (bash, git,
  tmux, neovim).
- **`dotfiles/host/`** copied by hand on a fresh Windows machine. Bootstrap
  doesn't manage these to avoid trampling other entries you have:
  - `dotfiles/host/zed-settings.json` -> `%APPDATA%\Zed\settings.json`
  - `dotfiles/host/ssh-config` -> `~\.ssh\config` (merge with existing entries)

## The host

Alpine Linux. Firewall, daily restic backups to Backblaze B2, and quiet daily
maintenance. The Caddyfile, port assignments, and post-receive hooks are all
generated from `projects.conf` so the server can be rebuilt from this repo alone.

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

Placed automatically by `bootstrap.ps1` (it prompts for them and writes into
the `bythewood-restic` volume). The `b2-env` file ends up looking like:

```sh
export B2_ACCOUNT_ID="<keyID>"
export B2_ACCOUNT_KEY="<applicationKey>"
export RESTIC_HOST="desktop"   # or "laptop"
```

Optional: drop the alpine repo password at `~/.restic/alpine-password`
(prompted for during bootstrap) so `status` can report on the alpine repo too.

### Alpine credentials

Placed by hand after `quickstart.sh` runs (the same paste-from-1Password
pattern), at `/root/.restic/password` and `/root/.restic/b2-env`. The alpine
`b2-env` should also have `RESTIC_HOST="alpine"`.

### Daily flow

```sh
backup     # take a snapshot from this machine
status     # check fleet health (both repos, every host) from anywhere
sync       # pull every repo under ~/code/ to GitHub HEAD
```

### Restore

Existing data is moved aside to `~/before-restore-<UTC-ISO>/` (webdev) or
`/root/before-restore-<UTC-ISO>/srv/` (alpine) before restic writes the
snapshot back:

```sh
restore                                 # webdev (from inside the container)
ssh root@server /root/restore.sh --up   # alpine; --up auto-restarts containers
```

## Philosophy

- Keep defaults until they fail you.
- One repo, one root, everything grows from here.
- If it's not worth tending, remove it.

## License

BSD 2-Clause. See [LICENSE.md](LICENSE.md).

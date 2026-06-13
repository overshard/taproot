# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Taproot is a personal infrastructure repository containing dotfiles, a Docker development container, and Alpine Linux server provisioning. Everything grows from one root: dev environment config, deployment automation, and server management.

## Key Commands

**Set up the dev container on a Windows host (idempotent, safe to re-run):**
```powershell
irm https://raw.githubusercontent.com/overshard/taproot/main/containers/webdev/bootstrap.ps1 -OutFile bootstrap.ps1
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 laptop      # or "desktop"
powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 laptop -Restore   # also pulls B2 snapshot
```

The `-ExecutionPolicy Bypass` flag scopes to that one invocation; nothing on your system changes persistently.

**Build the dev container manually (bootstrap.ps1 does this for you):**
```sh
docker build --tag overshard/webdev:latest -f containers/webdev/Dockerfile .
```

**Provision a fresh Alpine server:**
```sh
scp -r hosts/alpine/ root@server:/root/alpine && ssh root@server "sh /root/alpine/quickstart.sh"
```

**Bootstrap project repos on server:**
```sh
sh hosts/alpine/srv/bootstrap.sh
```

There are no tests, linters, or build steps in this repo — it is pure configuration.

## Helper Scripts (inside the webdev container, in PATH at `~/scripts/`)

| Command | What it does |
|---|---|
| `restic-backup` | Manual restic backup to B2 (tags snapshot with `$RESTIC_HOST` from `~/.restic/b2-env`) |
| `restic-restore` | Pull latest snapshot from B2 into volumes; existing data archived first |
| `restic-status` | Last snapshot per host across both webdev and alpine restic repos, plus repo size |
| `code-sync` | `git fetch` + `git pull --ff-only` for every repo under `~/code/` (skips dirty/divergent), then clones any non-archived non-fork repos owned by overshard on GitHub that aren't local yet |
| `server-health-check` | SSH into alpine and run its `/root/server-health-check.sh` (apk log, restic stats, free, df, docker stats). Override target with `$ALPINE_HOST` |

## Architecture

- **`dotfiles/`** — Terminal and editor config (bash, git, tmux, neovim). Neovim config is Lua-based with a custom statusline. These get COPYed into the container at build time.
- **`containers/webdev/`** — Ubuntu 24.04 dev container with Node (apt, only for `npx playwright install`), Python 3 (pip + uv), Bun, Rust (rustup-managed stable toolchain with rust-analyzer, clippy, rustfmt — for the axum projects and the Claude Code rust-analyzer LSP plugin), Docker CLI, Playwright Chromium (under `/opt/playwright-browsers`, for the Claude playwright MCP), and standard dev tools (neovim, tmux, git, rsync, htop, nmap, unzip, etc.). Stays alive via `sleep infinity`; entered through `docker exec -it bythewood-webdev tmux` for the TUI workflow. `openssh-client` and the baked-in `~/.ssh/config` plus the volume-resident `home_key` exist only for outbound SSH (git over SSH, `server-health-check` into alpine); there is no sshd, so nothing connects into the container. Started with `docker run --init` so PID 1 reaps zombies left behind when tmux children exit. Helper scripts (`restic-backup`, `restic-restore`, `restic-status`, `code-sync`, `server-health-check`) are baked in at `/home/dev/scripts/` and on PATH. Host setup is automated by `bootstrap.ps1`.
- **`hosts/alpine/`** — Production server setup: Caddy (in Docker, auto HTTPS) on the shared `bythewood-edge` network for reverse-proxying, Docker Compose for services, restic backups to Backblaze B2, UFW firewall, push-to-deploy via git hooks.

## Deployed Projects

`hosts/alpine/srv/projects.conf` is the single source of truth. Format per line:
`name|github_repo|branch|has_data_dir|runs_migrations`. Current manifest:

| Project | Stack | Data dir | Migrations |
|---|---|---|---|
| `analytics` | Rust (axum) + Vite (Bun) + SQLite | yes | no |
| `blog.bythewood.me` | Rust (axum) + Vite (Bun) | no | no |
| `timelite` | Next.js + Bun (local-only, no backend) | no | no |
| `isaacbythewood.com` | Next.js + Bun (Pages Router, plain JS) | no | no |
| `status` | Rust (axum) + Vite (Bun) + SQLite | yes | no |
| `darkfurrow.com` | Rust (axum) + Vite (Bun) | no | no |
| `repos` | Rust (axum) + Vite (Bun) | no | no |
| `finance` | Rust (axum) + Vite (Bun) + SQLite | yes | no |

Every container listens on 8000 internally; Caddy reaches them by container name on the shared `bythewood-edge` Docker network, so there's no per-project port. Update repos or flags by editing `projects.conf` and re-running the relevant provisioning step. Post-receive hooks and the bootstrap script are generated from this file; the Caddyfile is hand-maintained at `srv/caddy/Caddyfile`.

## How Deployment Works

`quickstart.sh` reads `projects.conf` and generates one bare repo under `/srv/git/<name>.git/` per project with a post-receive hook. Pushing to that remote triggers: `git pull`, `docker compose up --build --detach`, then `docker network connect bythewood-edge <cid>` for every container ID returned by `docker compose ps -q` (resolved that way, not by name, so the attach works regardless of compose service name or `container_name`; idempotent because `compose up` recreates containers and drops external attachments), optional `manage.py migrate`, and `docker system prune`. Caddy itself runs as a container under `/srv/docker/caddy/` and is brought up once by `quickstart.sh`; ACME certs and account keys persist at `/srv/data/caddy/` (so they're covered by the daily restic snapshot), and Caddyfile edits get picked up via `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`.

## Conventions

- Commit messages are poetic and lowercase, reflecting the "taproot" metaphor
- Shell scripts target POSIX sh for Alpine compatibility
- Git is configured for rebase-on-pull
- Container volumes use `bythewood-*` prefix
- Only Caddy publishes host ports (80, 443, 443/udp). Every other container is reached through the shared `bythewood-edge` Docker network. UFW manages the host firewall; do not add `ports:` to a project compose file or it will be exposed publicly via Docker's iptables NAT

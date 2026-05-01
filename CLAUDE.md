# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Taproot is a personal infrastructure repository containing dotfiles, a Docker development container, and Alpine Linux server provisioning. Everything grows from one root: dev environment config, deployment automation, and server management.

## Key Commands

**Build the development container:**
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

## Architecture

- **`dotfiles/`** — Terminal and editor config (bash, git, tmux, neovim). Neovim config is Lua-based with a custom statusline. These get COPYed into the container at build time.
- **`containers/webdev/`** — Ubuntu 24.04 dev container with Node 22, Python 3 (pip + uv), Bun, Docker-in-Docker, Playwright Chromium (under `/opt/playwright-browsers`, for the Claude playwright MCP), and standard dev tools (neovim, tmux, git, rsync, htop, nmap, unzip, etc.). Stays alive via `sleep infinity`; entered through `docker exec -it ... tmux` for the TUI workflow or over SSH on host port 2222 for editor remote-dev. `entrypoint.sh` starts sshd before exec'ing CMD; host keys persist in the `bythewood-ssh` volume so fingerprints survive rebuilds. Started with `docker run --init` so PID 1 reaps zombies left behind when tmux/sshd children exit.
- **`hosts/alpine/`** — Production server setup: Caddy reverse proxy (auto HTTPS), Docker Compose for services, restic backups to Backblaze B2, UFW firewall, push-to-deploy via git hooks.

## Deployed Projects

`hosts/alpine/srv/projects.conf` is the single source of truth. Format per line:
`name|port|github_repo|branch|has_data_dir|runs_migrations`. Current manifest:

| Project | Port | Stack | Data dir | Migrations |
|---|---|---|---|---|
| `analytics` | 8000 | Django + Vite (Bun) + SQLite | yes | yes |
| `blog.bythewood.me` | 8100 | Flask (uv) + Vite (Bun) | no | no |
| `timelite` | 8200 | Next.js + Bun (local-only, no backend) | no | no |
| `isaacbythewood.com` | 8300 | Next.js + Bun (Pages Router, plain JS) | no | no |
| `status` | 8400 | Django + Vite (Bun) + SQLite | yes | yes |
| `darkfurrow.com` | 8500 | Flask (uv) | no | no |

Update ports, repos, or flags by editing `projects.conf` and re-running the relevant provisioning step — every downstream artifact (Caddyfile routes, post-receive hooks, bootstrap script) is generated from this file.

## How Deployment Works

`quickstart.sh` reads `projects.conf` and generates one bare repo under `/srv/git/<name>.git/` per project with a post-receive hook. Pushing to that remote triggers: `git pull`, `docker compose up --build --detach`, optional `manage.py migrate`, and `docker system prune`. The Caddyfile proxies each project's subdomain to its bound port on `127.0.0.1`.

## Conventions

- Commit messages are poetic and lowercase, reflecting the "taproot" metaphor
- Shell scripts target POSIX sh for Alpine compatibility
- Git is configured for rebase-on-pull
- Container volumes use `bythewood-*` prefix
- Docker daemon iptables are disabled; UFW handles firewall rules instead

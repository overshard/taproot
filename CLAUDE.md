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
- **`containers/webdev/`** — Ubuntu 24.04 dev container running PostgreSQL 16 + Redis via supervisord. Includes Node 22 (yarn via corepack), Python 3 (pip + uv), and standard dev tools.
- **`hosts/alpine/`** — Production server setup: Caddy reverse proxy (auto HTTPS), Docker Compose for services, Borg backups, UFW firewall, push-to-deploy via git hooks.

## How Deployment Works

`hosts/alpine/srv/projects.conf` is the single source of truth for deployed projects. Each entry defines a project name, port, GitHub repo, and whether it needs data dirs or migrations. The bootstrap script creates bare git repos at `/srv/git/` with post-receive hooks that auto-deploy by pulling changes and running `docker compose up --build --detach`.

## Conventions

- Commit messages are poetic and lowercase, reflecting the "taproot" metaphor
- Shell scripts target POSIX sh for Alpine compatibility
- Git is configured for rebase-on-pull
- Container volumes use `bythewood-*` prefix
- Docker daemon iptables are disabled; UFW handles firewall rules instead

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
├── dotfiles/       the soil — bash, git, neovim, tmux
├── containers/     the vessel — development environments
└── hosts/          the field — server provisioning and maintenance
    └── alpine/
        ├── quickstart.sh       provision a fresh server
        ├── etc/caddy/          the single gate — Caddyfile
        ├── etc/docker/         daemon configuration
        ├── etc/periodic/       daily backups and upgrades
        ├── root/               health checks
        └── srv/
            ├── projects.conf   the manifest — every project, port, repo
            └── bootstrap.sh    clone all repos into a fresh code directory
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

An Ubuntu-based development workstation with everything already in the ground:
Python (uv), Node, Bun, Docker, neovim, tmux, Claude, and Playwright Chromium
(for the Claude playwright MCP). Kept alive with `sleep infinity`; enter
through `docker exec -it bythewood-webdev tmux`.

Build from the repo root so the dotfiles are in the build context:

```sh
docker build --tag overshard/webdev:latest -f containers/webdev/Dockerfile .

docker volume create --name bythewood-code
docker volume create --name bythewood-claude
docker volume create --name bythewood-ssh
docker volume create --name bythewood-restic

docker run --detach --init --restart unless-stopped --name bythewood-webdev \
    --volume bythewood-code:/home/dev/code \
    --volume bythewood-claude:/home/dev/.claude \
    --volume bythewood-ssh:/home/dev/.ssh \
    --volume bythewood-restic:/home/dev/.restic \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    -p 8000:8000 \
    overshard/webdev:latest

# Copy SSH keys into the volume (first time only, PowerShell)
docker cp $HOME/.ssh/home_key bythewood-webdev:/home/dev/.ssh/home_key
docker cp $HOME/.ssh/home_key.pub bythewood-webdev:/home/dev/.ssh/home_key.pub
docker exec bythewood-webdev sudo chown dev:dev /home/dev/.ssh/home_key /home/dev/.ssh/home_key.pub
docker exec bythewood-webdev chmod 600 /home/dev/.ssh/home_key

docker exec -it bythewood-webdev tmux
```

## The dotfiles

Minimal by intention. I respect defaults and only override what earns it.
Baked into the container at build time via COPY — no bootstrap script needed.

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
bucket (`overshard-backups`) using restic, one repo per host:

| Host | Repository | Paths backed up |
|---|---|---|
| webdev | `b2:overshard-backups:webdev` | `~/.claude`, `~/code`, `~/.ssh` |
| alpine | `b2:overshard-backups:alpine` | `/srv/git`, `/srv/docker`, `/srv/data` |

Each host has its own application key (scoped to the bucket) and its own
restic password — both stored in 1Password. Retention is 7 daily / 4 weekly /
6 monthly snapshots, pruned after each backup.

Place credentials before backups will run:

```sh
# webdev (paste from 1Password, then Ctrl-D)
docker exec -i bythewood-webdev tee /home/dev/.restic/password > /dev/null
docker exec -i bythewood-webdev tee /home/dev/.restic/b2-env > /dev/null
docker exec bythewood-webdev chmod 600 /home/dev/.restic/password /home/dev/.restic/b2-env

# alpine
ssh root@server "cat > /root/.restic/password && chmod 600 /root/.restic/password"
ssh root@server "cat > /root/.restic/b2-env && chmod 600 /root/.restic/b2-env"
```

`b2-env` contents (both hosts):

```sh
export B2_ACCOUNT_ID="<keyID>"
export B2_ACCOUNT_KEY="<applicationKey>"
```

Run a backup manually:

```sh
docker exec -it bythewood-webdev /home/dev/backup.sh   # webdev (manual)
ssh root@server /etc/periodic/daily/restic-autobackup  # alpine (also runs daily)
```

Restore the latest snapshot. Existing data is moved aside to
`~/before-restore-<UTC-ISO>/` (webdev) or `/root/before-restore-<UTC-ISO>/srv/`
(alpine) before restic writes the snapshot back:

```sh
docker exec -it bythewood-webdev /home/dev/restore.sh
ssh root@server /root/restore.sh
```

## Philosophy

- Keep defaults until they fail you.
- One repo, one root, everything grows from here.
- If it's not worth tending, remove it.

## License

BSD 2-Clause. See [LICENSE.md](LICENSE.md).

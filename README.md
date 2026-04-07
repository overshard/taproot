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

## The container

An Ubuntu-based development workstation with everything already in the ground:
Python, Node, PostgreSQL, Redis, Docker, neovim, tmux, and Claude. Managed by
supervisord. Enter through tmux.

Build from the repo root so the dotfiles are in the build context:

```sh
docker build --tag overshard/webdev:latest -f containers/webdev/Dockerfile .

docker volume create --name bythewood-code
docker volume create --name bythewood-claude
docker volume create --name bythewood-ssh

docker run --detach --restart unless-stopped --name bythewood-webdev \
    --volume bythewood-code:/home/dev/code \
    --volume bythewood-claude:/home/dev/.claude \
    --volume bythewood-ssh:/home/dev/.ssh \
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

Alpine Linux. Firewall, backups, and quiet daily maintenance. The Caddyfile,
port assignments, and post-receive hooks are all generated from `projects.conf`
so the server can be rebuilt from this repo alone.

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

## Philosophy

- Keep defaults until they fail you.
- One repo, one root, everything grows from here.
- If it's not worth tending, remove it.

## License

BSD 2-Clause. See [LICENSE.md](LICENSE.md).

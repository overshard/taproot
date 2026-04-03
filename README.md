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

docker run --detach --restart unless-stopped --name bythewood-webdev \
    --volume bythewood-code:/home/dev/code \
    --volume bythewood-claude:/home/dev/.claude \
    --volume ~/.ssh:/home/dev/.ssh:ro \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    -p 8000:8000 \
    overshard/webdev:latest

docker exec -it bythewood-webdev tmux
```

## The dotfiles

Minimal by intention. I respect defaults and only override what earns it.
Baked into the container at build time via COPY — no bootstrap script needed.

## The host

Alpine Linux. Firewall, backups, and quiet daily maintenance. Push the files
over and provision from here:

```sh
scp -r hosts/alpine/ root@your-server:/root/alpine
ssh root@your-server "cd /root/alpine && sh quickstart.sh"
```

## Philosophy

- Keep defaults until they fail you.
- One repo, one root, everything grows from here.
- If it's not worth tending, remove it.

## License

BSD 2-Clause. See [LICENSE.md](LICENSE.md).

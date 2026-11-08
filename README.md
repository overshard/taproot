# taproot

Dotfiles, the container I write code in, and the configs that make a machine
mine. The container also runs pi with a local coding model on the desktop's
GPU. Nothing is deployed from here, every site I run lives in
[orchard](https://github.com/overshard/orchard).

## Requirements

Docker. On Windows that's docker-ce in a Debian WSL distro, which `make wsl`
sets up, see [docs/wsl.md](docs/wsl.md). For pi, an NVIDIA card and the
container toolkit.

## Running it

Everything is a make target and `make help` lists them.

```sh
make wsl        # the Debian host, docker-ce, timers, once per machine
make install    # build webdev, enter the B2 credentials, restore from backup
make update     # rebuild the image and replace the running container
make up         # create whatever is missing and start it, safe to re-run
make doctor     # what's running, what's broken, what to type
make shell      # attach via tmux
make models     # Ornith's weights for pi, once
```

`make update` rebuilds without cache, except the llama.cpp CUDA build, so
Debian's security fixes come in with it, and it works from inside the container it's replacing. Your shell drops for
a couple of seconds and `docker exec -it bythewood-webdev tmux` brings you back.

From a dead machine back to running sites is [docs/recovery.md](docs/recovery.md).
Backups and the helper scripts are in [docs/backups.md](docs/backups.md), the
local model in [docs/pi.md](docs/pi.md), and the dotfiles and neovim
keys in [docs/dotfiles.md](docs/dotfiles.md).

## Layout

```
taproot/
├── Makefile             every command
├── docs/                the host, recovery, backups, pi, dotfiles
├── dotfiles/            bash, git, neovim, tmux, claude
└── containers/
    └── webdev/          Debian 13 dev image, scripts copied to ~/scripts/
```

## Things that will bite you

- `--init` is required, or tmux leaves zombies behind for the life of the
  container.
- The mounted `docker.sock` is root-owned mode 660, so docker needs `sudo` and
  the docker group doesn't help. Where it needs none, `make up SUDO=`.
- Bind mounts of paths under `/home/dev` silently mount an empty directory,
  since the daemon resolves them on the host. Use named volumes.
- Docker Desktop's WSL integration has to be off for this distro, or its proxy
  replaces `/run/docker.sock` and takes it down with the engine.
- Debian's `/etc/profile` assigns `PATH` outright, so a login shell drops what
  `ENV PATH` added. The image carries a `profile.d` snippet for it.
- pi's model fills most of an 8 GB card while a pi is open, and shares it with
  orchard's llm gateway, see [docs/pi.md](docs/pi.md).
- The repo password for backups can't be recovered, so keep it in Bitwarden
  and on the paper in the safe.
- The `dev` user is UID 1001 to match the volumes, so don't clean up the
  `-u 1001`.

## License

BSD 2-Clause. See [LICENSE.md](LICENSE.md).

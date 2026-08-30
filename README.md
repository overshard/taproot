# taproot

Dotfiles, containers, and the configs that make a machine mine. Two containers:
the one I write code in, and one that runs a local coding model on the desktop's
GPU.

Nothing is deployed from this repo. Every site I run lives in
[orchard](https://github.com/overshard/orchard), which carries its own edge and
its own deploy story.

## Requirements

Docker. For the AI container, an NVIDIA card and the container toolkit. A git
key at `~/.ssh/home_key` that is on GitHub.

## Getting it running

Add `C=aiagent` to any of these to work on the other container. It defaults to
`webdev`, which is the one you live in.

### From nothing

A machine that has never run this:

```sh
make up
docker cp $HOME/.ssh/home_key bythewood-webdev:/home/dev/.ssh/home_key
docker exec bythewood-webdev sh -c "chmod 700 /home/dev/.ssh && chmod 600 /home/dev/.ssh/home_key"
docker exec -it bythewood-webdev restic-setup
docker exec -it bythewood-webdev restic-restore
make shell
```

`make up` makes the volumes, builds the image and starts the container. The
three lines after it are the parts no image can carry: your git key, your backup
credentials, and the data itself. `restic-restore` is the only way the memory
vault comes back, since that repo has no git remote anywhere.

The key's `600` matters. ssh refuses anything looser, and a key copied off
Windows arrives with no usable mode, which is why the chmod is its own line.

On a machine with an NVIDIA card, pull the weights and bring the agent up too.
Skip it otherwise, nothing else depends on it:

```sh
make models
make up C=aiagent
```

### After you change something

A new tool in the Dockerfile, a dotfile edit, a Debian update worth picking up:

```sh
make update
```

This rebuilds and replaces. It works from inside the container it is replacing,
so your shell drops for a couple of seconds and `docker exec -it
bythewood-webdev tmux` from the host brings you back. Volumes are untouched.

### When something is broken

```sh
make doctor
```

Read-only. It prints every container, volume and credential, and next to
anything wrong, the command that fixes it. Most answers are `make up`, which is
idempotent and repairs as readily as it installs.

## Commands

| Target | What it does |
|---|---|
| `up` | Create whatever is missing and start it. Safe to re-run, and the repair command |
| `update` | Rebuild the image and replace the running container |
| `doctor` | What exists, what is running, what to type next |
| `shell` | Attach via tmux |
| `stop` | Stop it without replacing anything |
| `models` | Fetch the weights once; the only step that needs the network |
| `dotfiles` | Link claude skills and the status line into the volume |

All except `models` and `dotfiles` take `C=webdev` (the default) or `C=aiagent`.

The docker socket is root-owned, so every command goes through `sudo`. On a host
where docker needs none, turn it off: `make up SUDO=`.

## Layout

```
taproot/
├── Makefile                        build, swap, and link everything below
├── dotfiles/                       bash, git, neovim, tmux, claude
└── containers/
    ├── webdev/
    │   ├── Dockerfile              Debian 13 dev image
    │   └── scripts/                copied to ~/scripts/ in the container
    └── aiagent/
        ├── Dockerfile              Debian 13 + llama.cpp CUDA + pi, loopback only
        └── scripts/
```

Both containers are Debian 13, both run as UID 1001, and both mount
`bythewood-code`, so they see the same `~/code`.

| | `webdev` | `aiagent` |
|---|---|---|
| For | writing and building | running a local coding agent |
| Toolchains | Go, uv, Bun, typst, Docker CLI, Playwright | none of its own; borrows webdev's |
| GPU | no | `--gpus all`, required |
| Publishes | 8000, for dev servers | nothing |
| Image | 3.5 GB | 2.2 GB |

Everything in `dotfiles/` is baked into the images at build time. The Claude
skills and status line are the exception, linked by `make dotfiles`, because
`/home/dev/.claude` is a volume and shadows whatever the image put there.

## Helper scripts

All in `~/scripts/` and on `PATH`:

| Command | What it does |
|---|---|
| `restic-setup`   | Check the B2 credentials, and walk through entering them if they are missing or wrong |
| `restic-backup`  | Manual restic backup to B2; snapshot tagged with `$RESTIC_HOST` |
| `restic-restore` | Pull latest snapshot from B2; existing data archived first |
| `restic-status`  | Last snapshot per host across both restic repos, plus repo size |
| `code-sync`      | Pull every repo under `~/code/`, then clone any new ones from GitHub |

In `aiagent`, `webdev-exec` runs a command over in `webdev` against the same
source tree. `go`, `gofmt` and `bun` are symlinks to it, so those just work.

## The aiagent container

Qwen3.5-9B at 128k context on a llama.cpp CUDA server, plus the
[pi](https://pi.dev) coding agent pointed at it. Sized for an 8GB Ampere card.
The server binds loopback and publishes nothing, so only pi inside the container
can reach it and it needs no API key.

```sh
make models             # once, the only step that reaches Hugging Face
make up C=aiagent
make shell C=aiagent    # then type: pi
make stop C=aiagent     # frees the VRAM
```

Serving a different model needs no rebuild, just llama-server flags appended to
the run:

```sh
docker run --rm --gpus all --volume bythewood-models:/models overshard/aiagent:latest -hf <repo>:<quant> --alias local
```

## Backups

The webdev container backs up to a Backblaze B2 bucket (`overshard-backups`)
using restic. Retention is 7 daily, 4 weekly and 6 monthly per host, pruned
after each backup. Passwords and B2 keys live in 1Password.

There is one repository, `b2:overshard-backups:webdev`, holding per-machine
snapshots of `~/.claude`, `~/code` and `~/.ssh` from desktop and laptop, each
tagged with `$RESTIC_HOST`.

`restic-setup` is the way in. It reports what is set, verifies it by actually
opening the repository, prompts for anything missing, and writes both files at
`0600`. It also carries the instructions for minting a fresh B2 application key.

```sh
restic-backup   # take a snapshot from this machine
restic-status   # check the repo from anywhere
restic-restore  # existing data moves to ~/before-restore-<UTC>/ first
```

**The repo password is not recoverable.** Lose it and the snapshots in that
repository are lost with it. It lives in 1Password.

## Things that will bite you

`--init` is required. Without a real PID 1, tmux leaves zombies behind and they
accumulate for the life of the container.

The mounted `docker.sock` is `root:root` mode 660, so docker commands inside
need `sudo`. Being in the docker group does not help.

Bind mounts of paths under `/home/dev` do not work from inside the container.
The daemon is Docker Desktop on the Windows host and resolves the source path
against its own filesystem, so it silently mounts an empty directory instead of
failing. Named volumes are what work.

Debian's `/etc/profile` assigns `PATH` outright rather than appending, so a login
shell (which every tmux pane is) drops whatever `ENV PATH` added. Both images
carry a `profile.d` snippet for this, and neither it nor the `ENV` alone is
enough.

`--gpus all` on aiagent or it loads nothing at all. Without the driver injection
`llama-server` cannot find `libcuda.so.1` and exits before anything else.

Weights plus a 128k `q4_0` KV cache sit at about 96% of an 8 GB card, so a
second CUDA process will not fit beside it. `make stop C=aiagent` frees it.

The `dev` user is UID 1001 to match the volumes. Do not clean up the `-u 1001`.

## License

BSD 2-Clause. See [LICENSE.md](LICENSE.md).

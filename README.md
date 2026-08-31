# taproot

Dotfiles, containers, and the configs that make a machine mine. Two containers:
the one I write code in, and one that runs a local coding model on the desktop's
GPU.

Nothing is deployed from this repo. Every site I run lives in
[orchard](https://github.com/overshard/orchard), which carries its own edge and
its own deploy story.

## Requirements

Docker, and a git key at `~/.ssh/home_key` that is on GitHub. For the AI
container, an NVIDIA card and the container toolkit.

## Getting it running

Everything is a make target and there are no scripts to invoke by hand. Add
`C=aiagent` to any of the container ones to work on the other container, it
defaults to `webdev`, which is the one you live in.

### From nothing

A machine that has never run this:

```sh
make install
```

That makes the volumes, builds the image, starts the container, copies the git
key in, walks through the backup credentials, and pulls everything back from the
latest snapshot. That last step matters because not everything under `~/code`
has a git remote to pull from, so restic is the only copy of it.

The credentials step offers a generated repo password if there isn't one yet, so
there's nothing to invent. Take it with enter and put it in 1Password before you
move on, because it isn't recoverable. If the machine is joining backups that
already exist, paste that repository's own password instead. `make password`
prints a fresh suggestion any time, and writes nothing.

Every step of `install` is also its own target, so a half-finished setup just
wants the one that failed:

```sh
make key       # copy in ~/.ssh/home_key, or make key KEY=/path/to/key
make restic    # enter or repair the B2 credentials
make restore   # pull the data back down
```

The key's `600` matters. ssh refuses anything looser, and a key copied off
Windows arrives with no usable mode, so `make key` sets it rather than trusting
what turns up.

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
so your shell drops for a couple of seconds and `make shell` from the host brings
you back. Volumes are untouched.

### When something is broken

```sh
make doctor
```

Read-only. It prints every container, volume and credential, and next to
anything wrong, the make target that fixes it. Most answers are `make up`, which
is idempotent and repairs as readily as it installs.

## Commands

| Target | What it does |
|---|---|
| `install` | A machine that has never run this, start to finish |
| `up` | Create whatever is missing and start it. Safe to re-run, and the repair command |
| `update` | Rebuild the image and replace the running container |
| `doctor` | What exists, what is running, what to type next |
| `shell` | Attach via tmux |
| `build` | Build the image without touching the container |
| `stop` | Stop it without replacing anything |
| `key` | Copy the git ssh key in from this machine |
| `restic` | Enter or repair the B2 backup credentials |
| `password` | Print a suggested password to paste into 1Password |
| `backup` | Take a restic snapshot now |
| `snapshots` | Last snapshot per host, and what the repo costs |
| `restore` | Pull everything back from the latest snapshot |
| `sync` | Pull every repo under `~/code`, clone any new ones |
| `dotfiles` | Link claude skills and the status line into the volume |
| `models` | Fetch the weights once, the only step that needs the network |
| `serve MODEL=` | Run a different model without rebuilding |

`up`, `update`, `doctor`, `shell`, `build` and `stop` take `C=webdev` (the
default) or `C=aiagent`. The rest are webdev's.

The docker socket is root-owned, so every command goes through `sudo`. On a host
where docker needs none, turn it off: `make up SUDO=`.

## Layout

```
taproot/
├── Makefile                        every command in this README
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
| Toolchains | Go, uv, Bun, typst, Docker CLI, gh, Playwright | none of its own, it borrows webdev's |
| GPU | no | `--gpus all`, required |
| Publishes | 8000, for dev servers | nothing |
| Image | 3.5 GB | 2.2 GB |

Everything in `dotfiles/` is baked into the images at build time. The Claude
skills and status line are the exception, linked by `make dotfiles`, because
`/home/dev/.claude` is a volume and shadows whatever the image put there.

## Helper scripts

The make targets are wrappers around these, which are in `~/scripts/` and on
`PATH` inside the container, so they can be typed directly once you are in
there:

| Command | Target | What it does |
|---|---|---|
| `restic-setup`   | `make restic` | Check the B2 credentials, and walk through entering them if they are missing or wrong |
| `restic-backup`  | `make backup` | Manual restic backup to B2, snapshot tagged with `$RESTIC_HOST` |
| `restic-restore` | `make restore` | Pull latest snapshot from B2, existing data archived first |
| `restic-status`  | `make snapshots` | Last snapshot per host, plus repo size |
| `code-sync`      | `make sync` | Pull every repo under `~/code/`, then clone any new ones from GitHub |

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

Serving a different model needs no rebuild, just a one-off run against the same
weights volume:

```sh
make serve MODEL=<hf-repo>:<quant>
```

## Backups

The webdev container backs up to a Backblaze B2 bucket (`overshard-backups`)
using restic. Retention is 7 daily, 4 weekly and 6 monthly per host, pruned
after each backup. Passwords and B2 keys live in 1Password.

There is one repository, `b2:overshard-backups:webdev`, holding per-machine
snapshots of `~/.claude`, `~/code` and `~/.ssh` from desktop and laptop, each
tagged with `$RESTIC_HOST`.

`make restic` is the way in. It reports what is set, verifies it by actually
opening the repository, prompts for anything missing, and writes both files at
`0600`. It also carries the instructions for minting a fresh B2 application key.

```sh
make backup     # take a snapshot from this machine
make snapshots  # check the repo from anywhere
make restore    # existing data moves to ~/before-restore-<UTC>/ first
```

**NOTE:** the repo password is not recoverable. Lose it and the snapshots in
that repository are lost with it. It lives in 1Password.

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

# Taproot

What holds when the surface turns.

Dotfiles, containers, and the configs that make a machine mine.

## Three situations

**Nothing here yet.** A machine that has never run this. Needs Docker, and a
git key at `~/.ssh/home_key` that is on GitHub.

```sh
make up
docker cp $HOME/.ssh/home_key bythewood-webdev:/home/dev/.ssh/home_key
docker exec bythewood-webdev sh -c "chmod 700 /home/dev/.ssh && chmod 600 /home/dev/.ssh/home_key"
docker exec -it bythewood-webdev restic-setup
docker exec -it bythewood-webdev restic-restore
make shell
```

`make up` makes the volumes, builds the image and starts the container. The
three lines after it are the parts no image can carry: your git key, your
backup credentials, and the data itself. `restic-restore` is the only way the
memory vault comes back, because that repo has no git remote anywhere.

**Something changed.** A new tool in the Dockerfile, a dotfile edit, a Debian
update worth picking up.

```sh
make update
```

This rebuilds and replaces. It works from inside the container it is replacing:
your shell drops for a couple of seconds and `docker exec -it bythewood-webdev
tmux` from the host brings you back. Volumes are untouched, so nothing you care
about is in the container being thrown away.

**Something is broken.** Something is down, missing, or not working.

```sh
make doctor
```

Read-only. It prints every container, volume and credential, and next to
anything wrong, the command that fixes it. Most answers are `make up`, which is
idempotent and repairs as readily as it installs.

Add `C=aiagent` to any of the three to work on the other container. It defaults
to `webdev`, which is the one you live in.

## What is this?

The single deep root beneath everything I work on. Personal infrastructure for
the machines I tend: the development container I write code in, and the AI
container that runs a coding model on the desktop's GPU.

This is not a framework. It's a living configuration. It grows when something
changes and stays quiet when nothing needs to.

## Structure

```
taproot/
├── Makefile                        build, swap, and link everything below
├── dotfiles/                       the soil: bash, git, neovim, tmux, claude
└── containers/
    ├── webdev/
    │   ├── Dockerfile              the vessel: Debian 13 dev image
    │   └── scripts/                copied to ~/scripts/ in the container
    │       ├── restic-setup.sh         check and enter the B2 credentials
    │       ├── restic-backup.sh        manual restic snapshot to B2
    │       ├── restic-restore.sh       pull latest snapshot from B2
    │       ├── restic-status.sh        last snapshot per host across repos
    │       └── code-sync.sh            pull existing repos + clone new ones from GitHub
    └── aiagent/
        ├── Dockerfile              Debian 13 + llama.cpp CUDA + pi, loopback only
        └── scripts/                copied to ~/scripts/ in the container
            └── webdev-exec.sh          run a build tool over in webdev
```

## What runs where

Nothing is deployed from this repo any more. Every site I run lives in
[`orchard`](https://github.com/overshard/orchard), a monorepo served from the
desktop behind a Cloudflare Tunnel, and it carries its own edge (cloudflared
and Caddy) and its own deploy story. The Alpine server this repo used to
provision was cancelled in August 2026 and its `hosts/` tree removed with it.

What is left here is the two containers and the dotfiles they are built from.

## The Makefile

Everything is a target, so the long docker lines live in one place instead of
in a comment. `make` on its own lists them.

| Target | What it does |
|---|---|
| `up` | Create whatever is missing and start it. Safe to re-run, and the repair command |
| `update` | Rebuild the image and replace the running container |
| `doctor` | What exists, what is running, what to type next |
| `shell` | Attach via tmux |
| `stop` | Stop it without replacing anything |
| `models` | Fetch the weights once; the only step that needs the network |
| `dotfiles` | Link claude skills and the status line into the volume |

All except `models` and `dotfiles` take `C=webdev` (the default) or
`C=aiagent`.

The docker socket is root-owned, so every command goes through `sudo`. On a
host where docker needs none, turn it off: `make up SUDO=`.

## The two containers

Both are Debian 13, both run as UID 1001, and both mount `bythewood-code`, so
they see the same `~/code`. One is built to write code, the other to run a
model, and the one that runs the model borrows the other's toolchain across the
docker socket rather than carrying a copy.

| | `webdev` | `aiagent` |
|---|---|---|
| For | writing and building | running a local coding agent |
| Toolchains | Go, uv, Bun, typst, Docker CLI, Playwright | none of its own; borrows webdev's |
| GPU | no | `--gpus all`, required |
| Publishes | 8000, for dev servers | nothing |
| Image | 3.5 GB | 2.2 GB |

## The webdev container

A Debian 13 development workstation with everything already in the ground: Go,
Python (uv), Bun, Claude Code, Docker CLI, typst, neovim, tmux, restic, and
Playwright Chromium (driven by `playwright-cli`, not an MCP). No nodejs and no
npm; Bun runs Playwright, which was the last thing that needed them. No Rust
toolchain either, since every Rust project here is archived. Kept alive with
`sleep infinity`.

Your work lives in the `bythewood-*` volumes rather than in the container, so
the container itself is disposable. Delete it and make a new one whenever you
like; that is the normal way to pick up a new image.

```sh
make update    # rebuild the image and replace the container
make shell     # get in
make stop      # stop it, without replacing anything
```

### Things that are not obvious

- `--init` is required. Without a real PID 1, tmux leaves zombies behind and
  they accumulate for the life of the container.
- The mounted `docker.sock` is `root:root` mode 660, so docker commands inside
  need `sudo`. Being in the docker group does not help, so there is no docker
  group.
- `--publish` is what makes a dev server on port 8000 reachable from the host
  browser. Publishing a port on some *other* container does not reach this one;
  to curl a neighbour, share its network namespace with `--network container:<name>`.
- Bind mounts of paths under `/home/dev` do not work from inside the container.
  The daemon is Docker Desktop on the Windows host and resolves the source path
  against its own filesystem, where it does not exist, so it silently mounts an
  empty directory instead of failing. Named volumes are what work.
- Debian's `/etc/profile` assigns `PATH` outright rather than appending, so a
  login shell (which every tmux pane is) drops whatever `ENV PATH` added. Both
  images carry a `profile.d` snippet for this; neither it nor the `ENV` alone
  is enough.

### Helper scripts

All in `~/scripts/` and on `PATH`:

| Command | What it does |
|---|---|
| `restic-setup`   | Check the B2 credentials, and walk through entering them if they are missing or wrong |
| `restic-backup`  | Manual restic backup to B2; snapshot tagged with `$RESTIC_HOST` |
| `restic-restore` | Pull latest snapshot from B2; existing data archived first |
| `restic-status`  | Last snapshot per host across both restic repos, plus repo size |
| `code-sync`      | `git fetch && git pull --ff-only` for every repo under `~/code/`, then clones any non-archived non-fork repos owned by overshard on GitHub that aren't local yet |

## The aiagent container

Qwen3.5-9B at 128k context on a llama.cpp CUDA server, plus the
[pi](https://pi.dev) coding agent pointed at it. Sized for an 8GB Ampere card.
The server binds loopback and publishes nothing, so only pi inside the
container can reach it and it needs no API key.

```sh
make models             # once, the only step that reaches Hugging Face
make up C=aiagent
make shell C=aiagent    # then type: pi
make stop C=aiagent     # frees the VRAM
```

Serving a different model needs no rebuild, just llama-server flags appended
to the run:

```sh
docker run --rm --gpus all --volume bythewood-models:/models overshard/aiagent:latest -hf <repo>:<quant> --alias local
```

### Helper scripts

In `~/scripts/` and on `PATH`:

| Command | What it does |
|---|---|
| `webdev-exec` | Run a command in `webdev` against the same source tree; symlinked to `go`, `gofmt` and `bun`, so those just work |

### Things that are not obvious

- `--gpus all` or it loads nothing at all: without the driver injection
  `llama-server` cannot find `libcuda.so.1` and exits before anything else.
- Weights plus a 128k `q4_0` KV cache sit at about 96% of an 8 GB card, so a
  second CUDA process will not fit beside it. `make stop C=aiagent` frees it.
- The `q4_0` KV cache flags are load bearing, not tuning. Qwen3.5 is a hybrid
  attention model, so only 8 of its 32 layers hold a growing cache; at 128k
  that is about 1.2 GB quantized against roughly 4.3 GB at f16.
- **It has no toolchain and does not need one.** `go`, `gofmt` and `bun` on
  its `PATH` are symlinks to `webdev-exec`, which runs the real tool over in
  `webdev` against the same `bythewood-code` volume and translates
  `/home/ai/code` to `/home/dev/code` on the way. The agent types
  `go build ./...` and never learns any of this, which is the whole point: a
  9B model follows a familiar command and will not reliably assemble a
  `docker exec` from a paragraph of instructions. With `webdev` stopped the
  wrappers say so and exit 127, so an unbuildable session looks like an
  unbuildable session rather than a passing one.
- **The socket mount is host root.** The wrappers reach the daemon through
  `/var/run/docker.sock`, which is `root:root` 660, so `ai` has passwordless
  sudo for `/usr/bin/docker` and nothing else. The narrowing is tidiness, not
  security: anything that can talk to the daemon can start a privileged
  container. This is worth it here only because both containers are on one
  trusted desktop and the agent is working on the same code either way.
- An `AGENTS.md` is written to `/home/ai/AGENTS.md` by the Dockerfile itself,
  where pi finds it by walking up from its working directory. It earns its
  place: measured against this 9B, its absence produced a stale Vite major and
  a cgo SQLite driver that compiles and then fails at runtime; its presence
  fixed both. It is inline rather than in `dotfiles/` because nothing else
  uses it.

## A machine that has never run this before

The steps are at the top of this file, under **Three situations**. Two notes on
the parts that are not a `make` target, because neither can be:

The git key's `600` matters. ssh refuses anything looser, and a key copied off
Windows arrives with no usable mode, which is why the `chmod` is its own line
rather than something `docker cp` could have done.

`make up` links the Claude skills and status line for you, but only because it
runs `make dotfiles` after the container exists. They cannot be baked into the
image: `/home/dev/.claude` is a volume and shadows whatever the image put
there.

On a machine with an NVIDIA card, pull the weights and bring the agent up too.
Skip it on a machine without one; nothing else depends on it:

```sh
make models
make up C=aiagent
```

## The dotfiles

Minimal by intention. I respect defaults and only override what earns it.
Everything in **`dotfiles/`** is baked into the containers at build time via
COPY (bash, git, tmux, neovim). The Claude skills and status line are the one
exception, linked by `make dotfiles` because a volume shadows them.

## Backups

The webdev container backs up to a Backblaze B2 bucket (`overshard-backups`)
using restic:

| Repository | What's in it |
|---|---|
| `b2:overshard-backups:webdev` | Per-machine snapshots from desktop and laptop (`~/.claude`, `~/code`, `~/.ssh`). Each snapshot tagged with `$RESTIC_HOST` (`desktop` or `laptop`); retention applies per-machine. |
| `b2:overshard-backups:alpine` | Historical only. Daily snapshots from the cancelled server (`/srv/git`, `/srv/docker`, `/srv/data`); nothing writes to it any more. |

Retention: 7 daily, 4 weekly, 6 monthly per host, pruned after each backup.
Restic passwords and B2 application keys live in 1Password.

### Credentials

`restic-setup` is the way in. It reports what is currently set, verifies it by
actually opening the repository, and prompts for anything missing, writing both
files at `0600`:

```sh
restic-setup            # check, and fix whatever is wrong
restic-setup --check    # check only, quietly; this is what `make doctor` calls
```

It also carries the instructions for minting a fresh B2 application key, for
the day the one in 1Password has been revoked. There is nothing to hand-edit;
the two files it manages in the `bythewood-restic` volume are:

| File | What it holds |
|---|---|
| `~/.restic/b2-env` | `B2_ACCOUNT_ID`, `B2_ACCOUNT_KEY`, and `RESTIC_HOST` (`desktop` or `laptop`) |
| `~/.restic/password` | The webdev repo password |

Optional: drop the alpine repo password at `~/.restic/alpine-password` so
`restic-status` can still report on that repository. It holds the old server's
backup history even though the server itself is gone.

**The repo password is not recoverable.** Lose it and the snapshots in that
repository are lost with it. It lives in 1Password.

### Daily flow

```sh
restic-backup   # take a snapshot from this machine
restic-status   # check both repos from anywhere
code-sync       # pull every repo under ~/code/ + clone any new ones from GitHub
```

### Restore

Existing data is moved aside to `~/before-restore-<UTC-ISO>/` before restic
writes the snapshot back:

```sh
restic-restore
```

## Philosophy

- Keep defaults until they fail you.
- One repo, one root, everything grows from here.
- If it's not worth tending, remove it.

## License

BSD 2-Clause. See [LICENSE.md](LICENSE.md).

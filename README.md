# taproot

Dotfiles, containers, and the configs that make a machine mine. Two containers:
the one I write code in, and one that runs a local coding model on the desktop's
GPU.

Nothing is deployed from this repo. Every site I run lives in
[orchard](https://github.com/overshard/orchard), which carries its own edge and
its own deploy story.

## Requirements

Docker. On Windows that's docker-ce in a Debian WSL distro, which `make wsl`
sets up. For the AI container, an NVIDIA card and the container toolkit.

## Getting it running

Everything is a make target and there are no scripts to invoke by hand. Add
`C=aiagent` to any of the container ones to work on the other container, it
defaults to `webdev`, which is the one you live in.

### The Windows host

The host is a Debian distro under WSL running docker-ce, no Docker Desktop. It
is kept the way an ordinary Debian machine is kept, which means apt packages,
vendor apt repos where I want current versions, a systemd service, and config in
`/etc`. From PowerShell:

```sh
wsl --install -d Debian
```

If Docker Desktop is still installed, turn its WSL integration off for this
distro first, under Settings, Resources, WSL integration. Leaving it on is the
worst thing on this page. Its integration proxy replaces `/run/docker.sock` in
the distro with its own and then dies along with the engine, so dockerd keeps
running and nothing can reach it. It took a Windows reboot to clear.

`make wsl` checks the socket rather than the directory, because
`/mnt/wsl/docker-desktop` outlives an uninstall and only clears on the next
`wsl --shutdown`. A note about that directory is not a problem. A socket that
resolves into it is.

Then inside the distro:

```sh
sudo apt update && sudo apt install -y git make
git clone https://github.com/overshard/taproot && cd taproot
make wsl
```

That installs docker-ce, the compose plugin and the NVIDIA container toolkit from
Docker's and NVIDIA's own apt repos, registers the nvidia runtime in
`/etc/docker/daemon.json`, enables dockerd under systemd, puts me in the `docker`
group, and writes a hidden starter into the Windows Startup folder. It ends by
running `nvidia-smi` in a container, so a table with the card in it means the GPU
works. Install the NVIDIA driver on Windows only, never inside the distro.

dockerd needs systemd as PID 1. New Debian installs already have it, and if this
one doesn't then `make wsl` writes `[boot] systemd=true` into `/etc/wsl.conf` and
stops, because that needs a `wsl --shutdown` from PowerShell before it takes.

Something has to start the distro, because WSL has no autostart setting of its
own, and systemd only takes over once the distro is up. The Startup file does it
at sign-in, which means the sites come back when I log in rather than when the
machine powers on.

To start them at boot instead, register a Task Scheduler task from an admin
PowerShell:

```powershell
$a = New-ScheduledTaskAction -Execute C:\Windows\System32\wsl.exe -Argument '-d Debian --exec sleep infinity'
$t = New-ScheduledTaskTrigger -AtStartup
$p = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType S4U -RunLevel Highest
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'WSL Debian' -Action $a -Trigger $t -Principal $p -Settings $s -Force
```

`S4U` is what Task Scheduler calls "run whether the user is logged on or not"
without storing a password, and the zero time limit matters because a task that
runs `sleep infinity` would otherwise be killed after three days. The distro is
registered to my user rather than to the machine, so the task has to run as me
and not as SYSTEM. Rerunning `make wsl` after this removes the Startup file,
since the two do the same job, and from then on it reports the task instead of
telling me how to make one. To go back to starting at sign-in:

```powershell
schtasks.exe /delete /tn "WSL Debian" /f
```

then rerun `make wsl` and it writes the Startup file again.

`make wsl` ends by printing the Windows side it can't do from in here. All of it
lives in `%USERPROFILE%\.wslconfig`, which WSL reads only when the VM starts, so
a change needs a `wsl --shutdown`:

```ini
[general]
instanceIdleTimeout=-1
distributionInstallPath=D:\\WSL
[wsl2]
swapFile=D:\\WSL\\swap.vhdx
```

`instanceIdleTimeout=-1` is what the WSL Settings app calls "Keep WSL running",
and without it the distro stops about 15 seconds after its last terminal closes
and takes every container with it. The other two put new distros and the swap
file on D: instead of C:.

Everything docker has, images and volumes included, lives in `/var/lib/docker`
inside the distro's single `ext4.vhdx`. To move all of it to another drive, from
PowerShell:

```sh
wsl --shutdown
wsl --manage Debian --move D:\WSL\Debian
wsl --shutdown
```

The second shutdown isn't a typo. The move starts the VM a few seconds before it
creates the new directory, so swap fails to come up that first time and the
Windows event log says it cannot find the path.

A long job stopping halfway for a sudo password is worth avoiding, so:

```sh
sudo visudo -f /etc/sudoers.d/$USER
```

with one line, `isaac ALL=(ALL:ALL) NOPASSWD: ALL`, and deleting the file undoes
it.

From there, `make install` in that clone does the rest, as below, without the
throwaway container.

### The machine is gone

Everything that matters is in two places: GitHub for `orchard` and `taproot`,
and the restic repository on B2 for `~/code` (both checkouts plus the memory
vault), `~/.claude` and `~/.ssh`. Nothing in a Docker volume is needed. Site
databases, logs, ntfy accounts, gateway keys and the Wikipedia snapshot are all
regenerated, the bare repos on `repos.bythewood.me` are all mirrored on GitHub,
and the tunnel credentials come back from Cloudflare.

**Get these out of Bitwarden before starting**, because nothing below works
without them and they are not in any backup:

- the B2 application key id and key, for `overshard-backups`
- the restic repository password for the `webdev` repo

Allow about an hour and a half, most of it waiting on downloads.

**1. Windows, about 10 minutes.** Install WSL and Debian, then set up the host:

```sh
wsl --install -d Debian
```

```sh
sudo apt update && sudo apt install -y git make
git clone https://github.com/overshard/taproot && cd taproot
make wsl
```

Follow what it prints. See **The Windows host** above for the `.wslconfig` keys
and the boot task.

**2. webdev and the restore, about 30 minutes.** Still in the distro:

```sh
make install
```

It creates the volumes, builds the image, starts the container, asks for the B2
credentials and the repo password, then pulls the snapshot down. That is about
2.8GB compressed. When it finishes, move in:

```sh
make shell
```

`~/code` is back, with both checkouts, the vault, and every site's `.env`.

**3. The sites, about 20 minutes.** Inside webdev:

```sh
cd ~/code/orchard && make install
```

It logs into Cloudflare in a browser, recovers the tunnel credentials for the
existing `orchard` tunnel, brings every container up, mints the gateway keys,
creates the ntfy accounts and initialises the login. Write down what it prints,
since the ntfy passwords and the auth recovery codes exist nowhere else.

**4. The long tail, whenever.** Neither is needed for a site to serve:

```sh
cd ~/code/orchard && make wiki     # 12.5GB, for chat's offline Wikipedia
cd ~/code/taproot && make models   # the weights for aiagent
```

**What will bite you.** The tunnel keeps its UUID only because step 3 recovers
the existing credentials rather than creating a second tunnel, so do not run
`sh edge/setup-tunnel.sh down` in a hurry, since that deletes the tunnel and
leaves every CNAME pointing at nothing. `make install` in orchard skips any
site that already has a `.env`, which is what you want after a restore and not
what you want on a genuinely new machine. And the restore refuses to run if the
code volume is not empty, so a half-finished attempt wants `make restore`
rather than `make install` a second time.

### From nothing

A new machine only needs Docker. There's no make or git on the host, so the
first run borrows a throwaway Debian container, hands it the host's docker
socket the same way webdev gets one, and does the install from in there. From
PowerShell or sh:

```sh
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock debian:trixie-slim bash
```

Then inside it:

```sh
apt-get update && apt-get install -y --no-install-recommends ca-certificates git make docker-cli docker-buildx
git clone https://github.com/overshard/taproot && cd taproot
make install
```

taproot is public so the clone needs no key, and the git key comes back with
the restore since `~/.ssh` is in the backup. You're root in there, so the
Makefile leaves off the `sudo` it uses everywhere else. When it finishes, `exit`
throws the Debian container away and you move into webdev for good:

```sh
docker exec -it bythewood-webdev tmux
```

From then on everything runs from `~/code/taproot` inside webdev, which the
restore brings back, or `code-sync` clones if there was nothing to restore.

`make install` makes the volumes, builds the image, starts the container, walks
through the backup credentials, and pulls everything back from the latest
snapshot. That last step matters because not everything under `~/code`
has a git remote to pull from, so restic is the only copy of it.

The credentials step offers a generated repo password if there isn't one yet, so
there's nothing to invent. Take it with enter and put it in Bitwarden before you
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

This rebuilds from scratch, so Debian's security fixes and the newest of
everything that isn't pinned come in with it, and then replaces. It takes a few
minutes for that reason. It works from inside the container it is replacing,
so your shell drops for a couple of seconds and
`docker exec -it bythewood-webdev tmux` from the host brings you back. Volumes
are untouched.

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
| `password` | Print a suggested password to paste into Bitwarden |
| `backup` | Take a restic snapshot now |
| `verify` | Read back 5% of the backup to prove it restores |
| `snapshots` | Last snapshot per host, and what the repo costs |
| `restore` | Pull everything back from the latest snapshot |
| `sync` | Pull every repo under `~/code`, clone any new ones |
| `dotfiles` | Link claude skills, the status line and the neovim config |
| `models` | Fetch the weights once, the only step that needs the network |
| `serve MODEL=` | Run a different model without rebuilding |

`up`, `update`, `doctor`, `shell`, `build` and `stop` take `C=webdev` (the
default) or `C=aiagent`. The rest are webdev's.

The docker socket is root-owned, so every command goes through `sudo` unless
make is already running as root. On a host
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

Everything in `dotfiles/` is baked into the images at build time. `make dotfiles`
then links three of them back out of the checkout, the Claude skills and status
line because `/home/dev/.claude` is a volume and shadows whatever the image put
there, and the neovim config so that editing it takes effect in the container
you're already in instead of waiting on a rebuild.

Neovim has a file tree sidebar on `F2`, which opens it, and pressing it again
from a file jumps into it, and again from inside it closes it. `F3` reveals the
file you're in. It
is nvim-tree, cloned into `pack/dev/start/` by the Dockerfile so there is no
plugin manager and nothing to fetch on first run. The keys for wherever you are
run across the top of the screen while the tree is open, or along the statusline
when it is closed, and `?` inside the tree lists all of them. It shows dotfiles
and git ignored files, everything except the inside of `.git`, and `H` and `I`
put those two filters back.

## Helper scripts

The make targets are wrappers around these, which are in `~/scripts/` and on
`PATH` inside the container, so they can be typed directly once you are in
there:

| Command | Target | What it does |
|---|---|---|
| `restic-setup`   | `make restic` | Check the B2 credentials, and walk through entering them if they are missing or wrong |
| `restic-backup`  | `make backup` | Restic backup to B2, run nightly by the host timer, snapshot tagged with `$RESTIC_HOST` |
| `restic-check`   | `make verify` | Read back 5% of the repo, run weekly by the host timer |
| `restic-alert`   | | Push a phone alert through ntfy, called when either timer fails |
| `restic-restore` | `make restore` | Pull latest snapshot from B2, existing data archived first |
| `restic-status`  | `make snapshots` | Last snapshot per host, plus repo size. `--age` is what doctor uses |
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
using restic. A systemd timer on the host runs it nightly and a second one
reads back 5% of the repo every Sunday. Either one failing sends a high
priority alert to the status topic on the phone, and `make doctor` says how old
the last snapshot is. Retention is 7 daily, 4 weekly and 6 monthly per host,
pruned after each backup. Passwords and B2 keys live in Bitwarden.

There is one repository, `b2:overshard-backups:webdev`, holding per-machine
snapshots of `~/.claude`, `~/code` and `~/.ssh` from desktop and laptop, each
tagged with `$RESTIC_HOST`.

`make restic` is the way in. It reports what is set, verifies it by actually
opening the repository, prompts for anything missing, and writes both files at
`0600`. It also carries the instructions for minting a fresh B2 application key.

```sh
make backup     # take a snapshot from this machine
make verify     # read back 5% of it
make snapshots  # check the repo from anywhere
make restore    # existing data moves to .before-restore-<UTC>/ inside each volume first
```

**NOTE:** the repo password is not recoverable. Lose it and the snapshots in
that repository are lost with it. It lives in Bitwarden, and on the paper in the safe.

## Things that will bite you

`--init` is required. Without a real PID 1, tmux leaves zombies behind and they
accumulate for the life of the container.

The mounted `docker.sock` is root-owned mode 660, so docker commands inside
need `sudo`. Being in the docker group does not help.

Bind mounts of paths under `/home/dev` do not work from inside the container.
The daemon runs on the host and resolves the source path against its own
filesystem, so it silently mounts an empty directory instead of failing. Named volumes are what work.

Debian's `/etc/profile` assigns `PATH` outright rather than appending, so a login
shell (which every tmux pane is) drops whatever `ENV PATH` added. Both images
carry a `profile.d` snippet for this, and neither it nor the `ENV` alone is
enough.

Docker Desktop's WSL integration must be off for any distro that runs its own
dockerd. Its proxy replaces `/run/docker.sock` with its own and takes it down
with the engine, which leaves a healthy dockerd that nothing can reach.

`--gpus all` on aiagent or it loads nothing at all. Without the driver injection
`llama-server` cannot find `libcuda.so.1` and exits before anything else.

Weights plus a 128k `q4_0` KV cache sit at about 96% of an 8 GB card, so a
second CUDA process will not fit beside it. `make stop C=aiagent` frees it.

The `dev` user is UID 1001 to match the volumes. Do not clean up the `-u 1001`.

## License

BSD 2-Clause. See [LICENSE.md](LICENSE.md).

# When the machine is gone

This is the whole way back from a dead or replaced desktop to every site
serving again. Allow about an hour and a half, most of it waiting on downloads.

## What comes back and what doesn't

GitHub has `orchard` and `taproot`, and the restic repository on B2 has `~/code`
(both checkouts, the memory vault and every site's `.env`), `~/.claude` and
`~/.ssh`. That's everything that matters.

Nothing in a Docker volume is backed up and that's on purpose. Site databases,
logs, ntfy accounts and gateway keys start fresh, the bare repos on
`repos.bythewood.me` mirror back from GitHub, the tunnel credentials come back
from Cloudflare, and the Wikipedia snapshot and model weights download again.
So analytics, status and logging history, chat's conversations and memory, and
llm's call log are gone for good. `memory/archive/local-only/` is kept off B2,
so it's gone too unless the old disk survived.

## What you need first

None of these are in any backup.

- Bitwarden. The master password and its 2FA recovery code are on the paper in
  the safe.
- Out of Bitwarden, the B2 application key id and key for `overshard-backups`,
  and the restic password for the `webdev` repo. The restic password is also on
  the paper, since without it the snapshots can't be opened by anyone.
- A Cloudflare login that can see both zones.

## 1. Windows, about 10 minutes

Install the NVIDIA driver on Windows and never inside the distro. Then from
PowerShell:

```sh
wsl --install -d Debian
```

and set up `%USERPROFILE%\.wslconfig` and the boot task as [wsl.md](wsl.md)
describes.

## 2. The Debian host, about 10 minutes

Inside the distro:

```sh
sudo apt update && sudo apt install -y git make
git clone https://github.com/overshard/taproot && cd taproot
make wsl
sudo systemctl stop restic-backup.timer
```

`make wsl` installs docker-ce and turns on the nightly backup timer. Stopping it
until step 5 matters, because a backup that runs while the restore is half done
takes a snapshot of a half empty tree, and that becomes the latest one.

## 3. webdev and the restore, about 30 minutes

Still in the distro, in the taproot clone:

```sh
make install
```

It creates the volumes, builds the image, starts the container, asks for the B2
key and the restic password, then pulls the newest snapshot down, which is a
couple of GB. Check the snapshot date it shows you is the one you expect. Then
move in:

```sh
make shell
make snapshots
```

## 4. The sites, about 20 minutes

Inside webdev:

```sh
cd ~/code/orchard && make install
```

It logs into Cloudflare in a browser and recovers the credentials for the
existing `orchard` tunnel, brings every container up, creates the ntfy accounts
and their tokens, and initialises the login. Put the ntfy passwords and the auth
recovery codes it prints into Bitwarden right away, they exist nowhere else.

`cert.pem` only covers one Cloudflare zone, so the second zone's hostnames fail
the first time. Run it again and pick the other zone in the browser:

```sh
make tunnel-login
make tunnel
```

chat and dash come back with the `LLM_KEY` from before in their `.env`, but the
gateway starts with no keys, so it turns them both away. Empty that line in
`sites/chat.bythewood.me/.env` and `sites/dash.bythewood.me/.env`, then:

```sh
make chat-key dash-key
make deploy SITE=chat.bythewood.me
make deploy SITE=dash.bythewood.me
```

Then point the ntfy app on the phone at `https://ntfy.bythewood.me` with the
reading account it printed, and subscribe to `status`, `logging` and `auth`.

## 5. Finish up

```sh
make doctor                                  # in ~/code/orchard
cd ~/code/taproot && make doctor && make verify
```

and back in the Debian host, turn the backups on again:

```sh
sudo systemctl start restic-backup.timer
```

The long tail can wait, since no site needs it to serve:

```sh
cd ~/code/orchard && make wiki     # 12.5GB, chat's offline Wikipedia
cd ~/code/taproot && make models   # the weights for aiagent
```

## On a machine that already has Docker

The laptop, or any Linux box, skips steps 1 and 2. There's no make or git on
the host, so borrow a throwaway Debian container with the host's docker socket:

```sh
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock debian:trixie-slim bash
apt-get update && apt-get install -y --no-install-recommends ca-certificates git make docker-cli docker-buildx
git clone https://github.com/overshard/taproot && cd taproot
make install
```

You're root in there, so the Makefile drops its `sudo`. When it's done, `exit`
throws the container away and `docker exec -it bythewood-webdev tmux` puts you
in webdev for good.

A machine that has never backed up before gets offered a generated restic
password. Take it, and put it in Bitwarden before moving on. A machine joining
the existing repo has to paste that repo's own password instead, since a new
one won't open it.

## If it stops halfway

Every step of `make install` is its own target, so rerun the one that failed:

```sh
make key       # copy in ~/.ssh/home_key, or make key KEY=/path/to/key
make restic    # enter or repair the B2 credentials
make restore   # pull the data back down
```

`make install` skips the restore when the code volume already has something in
it, so a half finished attempt wants `make restore` and not `make install`
again. `make restore` moves whatever is there into a `.before-restore-<UTC>/`
inside each volume before it writes, so nothing is lost. In orchard, `make
install` skips any site that already has a `.env`, which is right after a
restore. And don't run `sh edge/setup-tunnel.sh down` in a hurry, it deletes the
tunnel and leaves every CNAME pointing at nothing.

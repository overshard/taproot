# The vault hooks

My notes vault at `~/code/memory` gets written by Claude without me asking. Hooks in the claude container start a background scribe, and a nightly timer on the host catches whatever they missed and tidies up. Everything is in `dotfiles/claude/hooks/`.

## The scripts

| Script | What it does |
|---|---|
| `vault-claude.sh` | The one headless `claude -p` every job runs, on sonnet, and it logs one line per run |
| `vault-scribe.sh` | Hands a transcript's typed text since its last run to `vault-claude.sh` to write up |
| `vault-capture.sh` | The Stop, PreCompact and SessionEnd hook that starts the scribe in the background |
| `vault-digest.sh` | The SessionStart hook that puts the newest journal Open lines in front of Claude |
| `vault-sweep.sh` | The nightly job, the scribe over the last two days and then a tidy of changed notes |

Stop starts the scribe every 8 typed messages (`EVERY` in `vault-capture.sh`), and PreCompact and SessionEnd always start it. It runs detached with `setsid`, so the session never waits on it.

The `claude -p` flags in `vault-claude.sh` all have a reason. `--setting-sources ""` loads no settings, so our own hooks don't fire inside a scribe run and loop forever. `--no-session-persistence` keeps no transcript, so the sweep never reads a scribe run back. The API key env vars are unset, so it always runs on the claude.ai login and my subscription. `--bare` would be leaner but it only works with an API key.

## State and logs

Everything lives in `~/.claude/state/`, which is in the restic backed `.claude` volume.

- `vault-scribe/<session>` is how many transcript lines the scribe has written up for that session. Delete one to have the next run read the whole session again.
- `vault-scribe/runs.log` has one line per run with the exit code, turns and token counts.
- `vault-scribe/lock` is the flock that keeps two runs from committing at once.
- `vault-capture/<session>` is the message count at the last Stop that started a scribe.

## The hooks in settings.json

The live `~/.claude/settings.json` is machine-local, so these get copied in by hand from the template in `dotfiles/claude/settings.json`:

```json
"hooks": {
  "Stop":         [{"hooks": [{"type": "command", "command": "$HOME/code/taproot/dotfiles/claude/hooks/vault-capture.sh", "timeout": 10}]}],
  "PreCompact":   [{"hooks": [{"type": "command", "command": "$HOME/code/taproot/dotfiles/claude/hooks/vault-capture.sh", "timeout": 10}]}],
  "SessionEnd":   [{"hooks": [{"type": "command", "command": "$HOME/code/taproot/dotfiles/claude/hooks/vault-capture.sh", "timeout": 10}]}],
  "SessionStart": [{"matcher": "startup|clear|compact", "hooks": [{"type": "command", "command": "$HOME/code/taproot/dotfiles/claude/hooks/vault-digest.sh", "timeout": 10}]}]
}
```

Removing the `hooks` block turns all of it off.

## The host timer

Same as the restic ones, two plain units in `/etc/systemd/system/` on the host:

```ini
# vault-sweep.service
[Unit]
Description=record the day's Claude sessions in the vault
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
TimeoutStartSec=30min
ExecStart=/usr/bin/docker exec -u dev claude /home/dev/code/taproot/dotfiles/claude/hooks/vault-sweep.sh

# vault-sweep.timer
[Unit]
Description=nightly vault sweep

[Timer]
OnCalendar=*-*-* 05:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
```

After writing them, `sudo systemctl daemon-reload && sudo systemctl enable --now vault-sweep.timer`, and `disable --now` undoes it. Run one by hand with `sudo systemctl start vault-sweep.service` and read it with `journalctl -u vault-sweep`.

## Things that will bite you

- The container sets no `TZ`, so the scripts default it to `America/New_York` for journal dates and times.
- `--add-dir` takes more than one value, so a prompt after it gets read as a directory. Keep the prompt first.
- The sweep hands the tidy a list of notes over 8,000 words but never splits them on its own, it leaves an Open line instead.

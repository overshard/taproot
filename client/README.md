# This device

A thin client for my VPS. The work happens there, through Claude remote control
in the app or on claude.ai. This is for when something needs fixing by hand.

## After the VPS reboots

```sh
unlock-vps
```

Asks for the disk passphrase, which is in Bitwarden. Docker, the sites and
remote control all come back once it's unlocked.

## When remote control is down or Claude needs a fresh login

```sh
claude-vps
```

Opens Claude Code inside the VPS container. Run `/login` there if it asks.

## Getting a shell on the VPS

```sh
ssh vps
sudo docker exec -it -u dev claude bash
```

## How it's wired

- WireGuard runs as a service, `sudo systemctl status wg-quick@wg0`, with its
  config in `/etc/wireguard/wg0.conf`. The VPS is 10.77.0.1 over the tunnel.
- `ssh vps` uses this device's own key, `~/.ssh/id_ed25519`.
- `~/memory` is a read-only copy of the vault, pulled whenever Claude starts
  here. Only the VPS writes to it.
- `~/CLAUDE.md` tells Claude on this device the same things, and `~/AGENTS.md`
  tells pi or any other agent.
- `~/taproot/client/setup.sh` set all of this up, and running it again is safe.

## If something's off

- `ssh vps` hangs: the tunnel is down, `sudo systemctl restart wg-quick@wg0`.
- `unlock-vps` says it's already active: nothing to do.
- `ls ~/memory` is empty or old: `vault-pull`, then check `ssh vps` works.

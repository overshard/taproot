#!/bin/sh
#
# setup.sh
#
# Turns a bare Debian (a phone's terminal, WSL on a laptop or desktop) into a
# client for the VPS: WireGuard as a systemd service, an ssh key and a `vps`
# host, Claude Code, the claude-vps, unlock-vps and vault-pull scripts, and a
# Claude config that reads a read-only mirror of the vault.
#
#   client/setup.sh <this device's wg address> <vps endpoint ip> <vps wg public key>
#   client/setup.sh 10.77.0.4 203.0.113.10 abc...=
#   client/setup.sh             when /etc/wireguard/wg0.conf is already in place
#
# It prints this device's public keys at the end, and they go on the VPS
# before ssh will work. Safe to run again, nothing that exists is overwritten.

set -eu

case $# in
3) addr=$1 endpoint=$2 vpskey=$3 ;;
0) addr= ;;
*) sed -n '10,12p' "$0" | sed 's/^# *//' >&2; exit 2 ;;
esac
here=$(cd "$(dirname "$0")" && pwd)

sudo apt-get update -qq
sudo apt-get install -y -qq openssh-client git jq curl ca-certificates

# The path from home only carries 1280 byte packets, so the tunnel's MTU is
# 1220 to leave room for WireGuard's own header.
if [ -n "$addr" ] && ! sudo test -f /etc/wireguard/wg0.conf; then
    sudo apt-get install -y -qq wireguard-tools
    priv=$(wg genkey)
    sudo install -d -m 700 /etc/wireguard
    printf '[Interface]\nAddress = %s/32\nPrivateKey = %s\nMTU = 1220\n\n[Peer]\nPublicKey = %s\nEndpoint = %s:51820\nAllowedIPs = 10.77.0.1/32\nPersistentKeepalive = 25\n' \
        "$addr" "$priv" "$vpskey" "$endpoint" | sudo tee /etc/wireguard/wg0.conf >/dev/null
    sudo chmod 600 /etc/wireguard/wg0.conf
fi
sudo test -f /etc/wireguard/wg0.conf && sudo systemctl enable --now wg-quick@wg0

mkdir -p ~/.ssh ~/.local/bin && chmod 700 ~/.ssh
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C "$(hostname)"
grep -q '^Host vps$' ~/.ssh/config 2>/dev/null || printf 'Host vps\n  HostName 10.77.0.1\n  User debian\n  IdentityFile ~/.ssh/id_ed25519\n  ServerAliveInterval 60\n' >> ~/.ssh/config
chmod 600 ~/.ssh/config

install -m 755 "$here/claude-vps" "$here/unlock-vps" "$here/vault-pull" ~/.local/bin/
command -v claude >/dev/null || [ -x ~/.local/bin/claude ] || curl -fsSL https://claude.ai/install.sh | bash

# The client's own instructions live in the vault mirror, so editing them on
# the VPS reaches every device at its next pull.
[ -e ~/CLAUDE.md ] && [ ! -L ~/CLAUDE.md ] && mv ~/CLAUDE.md ~/CLAUDE.md.before-client
ln -sfn memory/client.md ~/CLAUDE.md
[ -e ~/README.md ] && [ ! -L ~/README.md ] && mv ~/README.md ~/README.md.before-client
ln -sfn "$here/README.md" ~/README.md
mkdir -p ~/.claude
if [ -f ~/.claude/settings.json ]; then
    jq -s '.[0] * .[1]' ~/.claude/settings.json "$here/claude-settings.json" > ~/.claude/settings.json.tmp
    mv ~/.claude/settings.json.tmp ~/.claude/settings.json
else
    cp "$here/claude-settings.json" ~/.claude/settings.json
fi

echo ""
echo "add these on the VPS, then run: vault-pull && ls ~/memory"
echo ""
[ -n "$addr" ] && echo "  wireguard peer: $(sudo sed -n 's/^PrivateKey = //p' /etc/wireguard/wg0.conf | wg pubkey) allowed-ips $addr/32"
echo "  ssh key:        $(cat ~/.ssh/id_ed25519.pub)"

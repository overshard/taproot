#!/bin/sh
#
# setup.sh
#
# Turns a bare Debian (a phone's terminal, WSL on a laptop or desktop) into a
# client for the VPS: WireGuard as a systemd service, an ssh key and a `vps`
# host, Claude Code, and the claude-vps and unlock-vps scripts.
#
#   client/setup.sh <this device's wg address> <vps endpoint ip> <vps wg public key>
#   client/setup.sh 10.77.0.4 203.0.113.10 abc...=
#
# It prints this device's WireGuard and ssh public keys at the end, and both
# go on the VPS before the tunnel or ssh will work. Safe to run again, since
# nothing that exists is overwritten.

set -eu

[ $# -eq 3 ] || { sed -n '9,10p' "$0" | sed 's/^# *//' >&2; exit 2; }
addr=$1 endpoint=$2 vpskey=$3
here=$(cd "$(dirname "$0")" && pwd)

sudo apt-get update -qq
sudo apt-get install -y -qq wireguard-tools openssh-client curl ca-certificates

# The path from home only carries 1280 byte packets, so the tunnel's MTU is
# 1220 to leave room for WireGuard's own header.
if ! sudo test -f /etc/wireguard/wg0.conf; then
    priv=$(wg genkey)
    sudo install -d -m 700 /etc/wireguard
    printf '[Interface]\nAddress = %s/32\nPrivateKey = %s\nMTU = 1220\n\n[Peer]\nPublicKey = %s\nEndpoint = %s:51820\nAllowedIPs = 10.77.0.1/32\nPersistentKeepalive = 25\n' \
        "$addr" "$priv" "$vpskey" "$endpoint" | sudo tee /etc/wireguard/wg0.conf >/dev/null
    sudo chmod 600 /etc/wireguard/wg0.conf
fi
sudo systemctl enable --now wg-quick@wg0

mkdir -p ~/.ssh ~/.local/bin && chmod 700 ~/.ssh
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C "$(hostname)"
grep -q '^Host vps$' ~/.ssh/config 2>/dev/null || printf 'Host vps\n  HostName 10.77.0.1\n  User debian\n  IdentityFile ~/.ssh/id_ed25519\n  ServerAliveInterval 60\n' >> ~/.ssh/config
chmod 600 ~/.ssh/config

install -m 755 "$here/claude-vps" "$here/unlock-vps" ~/.local/bin/
command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash

echo ""
echo "add these on the VPS, then run: ssh vps true"
echo ""
echo "  wireguard peer: $(sudo sed -n 's/^PrivateKey = //p' /etc/wireguard/wg0.conf | wg pubkey) allowed-ips $addr/32"
echo "  ssh key:        $(cat ~/.ssh/id_ed25519.pub)"

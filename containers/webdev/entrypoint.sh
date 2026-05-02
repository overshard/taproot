#!/bin/sh
# Runs as PID 1's child under tini (--init). Generates persistent host keys
# on first start so rebuilds don't churn fingerprints, wires authorized_keys
# from the user's existing pubkey, starts sshd, then exec's CMD.
set -e

HOST_KEY_DIR=/home/dev/.ssh/host_keys

# Check via sudo because $HOST_KEY_DIR is mode 700 root:root and dev can't
# traverse it — without sudo the test always reads as "missing" and we'd
# re-enter ssh-keygen on every start, which prompts to overwrite and crashes.
if ! sudo test -f "$HOST_KEY_DIR/ssh_host_ed25519_key"; then
    sudo mkdir -p "$HOST_KEY_DIR"
    sudo ssh-keygen -t ed25519 -f "$HOST_KEY_DIR/ssh_host_ed25519_key" -N "" -q
    sudo chmod 700 "$HOST_KEY_DIR"
    sudo chmod 600 "$HOST_KEY_DIR/ssh_host_ed25519_key"
    sudo chmod 644 "$HOST_KEY_DIR/ssh_host_ed25519_key.pub"
fi

# Reuse home_key as both outbound identity and inbound authorized key.
if [ -f /home/dev/.ssh/home_key.pub ] && [ ! -e /home/dev/.ssh/authorized_keys ]; then
    ln -s home_key.pub /home/dev/.ssh/authorized_keys
fi

sudo /usr/sbin/sshd

exec "$@"

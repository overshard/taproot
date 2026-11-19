#!/bin/bash
# Starts `claude mcp login orchard` in the background and prints the authorize URL.
# The login listens on a localhost port inside this container, so the browser
# that finishes the sign in has to be playwright-cli here and not Isaac's phone.
set -euo pipefail
dir=${1:?usage: start-login.sh <scratch dir>}
cd "$dir"
rm -f in.fifo login.log
mkfifo in.fifo
# The login reads stdin for a pasted redirect, so keep a writer open or it sees EOF.
(sleep 600 > in.fifo &)
(cd ~ && nohup script -qfc "claude mcp login orchard --no-browser" "$dir/login.log" < "$dir/in.fifo" > /dev/null 2>&1 &)
for _ in $(seq 20); do
	url=$(tr -d '\r' < login.log | grep -o 'https://mcp.bythewood.me/authorize[^]\x1b]*' | head -1 | sed 's/\x1b.*//' || true)
	[ -n "$url" ] && { echo "$url"; exit 0; }
	sleep 0.5
done
echo "no authorize URL, see $dir/login.log" >&2
exit 1

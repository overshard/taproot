#!/bin/sh
#
# ntfy-alert.sh
#
# Push an alert to the alerts topic on the phone. The host's systemd units call
# it through docker exec:
#
#   ntfy-alert "Title" "Message" [priority] [tags]
#
# It borrows status' write token, since the phone listens on alerts and ntfy
# has no other account that can publish there. The post goes over the
# orchard-edge bridge from orchard-util, because Caddy refuses publishes on the
# public hostname. The token goes in on stdin so it never shows in a process
# list.
#

set -u

title="${1:?usage: ntfy-alert title message [priority] [tags]}"
message="${2:?usage: ntfy-alert title message [priority] [tags]}"
priority="${3:-default}"
tags="${4:-warning}"

env_file="$HOME/code/orchard/sites/status.bythewood.me/.env"
token=$(sed -n 's/^NTFY_TOKEN=//p' "$env_file" 2>/dev/null)
if [ -z "$token" ]; then
    echo "no NTFY_TOKEN in $env_file, so no alert was sent" >&2
    exit 1
fi

printf 'Authorization: Bearer %s\n' "$token" |
    sudo docker run --rm -i --network orchard-edge orchard-util \
        curl -fsS -o /dev/null \
        -H @- \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        -d "$message" \
        http://orchard-ntfy:8000/alerts

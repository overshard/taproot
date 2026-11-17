#!/bin/sh
#
# vault-capture.sh
#
# Hooked to Stop, PreCompact and SessionEnd on the VPS. Stop starts the scribe
# once a session has had EVERY typed messages since it last did, and the other
# two always start it. The scribe runs detached so the session never waits.

EVERY=${EVERY:-8}
STATE=$HOME/.claude/state/vault-capture
SCRIBE=$(dirname "$0")/vault-scribe.sh

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty')
session=$(printf '%s' "$input" | jq -r '.session_id // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
[ -n "$session" ] && [ -r "$transcript" ] || exit 0

if [ "$event" = Stop ]; then
    # Typed user messages only, since tool results also arrive as type user.
    said=$(jq -c 'select(.type == "user" and (.message.content | type) == "string")' "$transcript" 2>/dev/null | wc -l)
    mkdir -p "$STATE"
    mark="$STATE/$session"
    last=$(cat "$mark" 2>/dev/null || echo 0)
    [ $((said - last)) -ge "$EVERY" ] || exit 0
    echo "$said" > "$mark"
fi

setsid -f "$SCRIBE" "$transcript" < /dev/null > /dev/null 2>&1
exit 0

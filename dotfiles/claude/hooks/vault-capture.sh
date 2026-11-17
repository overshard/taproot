#!/bin/sh
#
# vault-capture.sh
#
# A Stop hook for the VPS. When a session has had a few exchanges since the
# vault last got a commit, it holds the stop once and asks Claude to write them
# down, so the vault keeps up without anyone saying "journal". Quiet turns pass.
#
# VAULT is the repo to watch and EVERY is how many user messages may go
# unrecorded before it asks.

VAULT=${VAULT:-$HOME/code/memory}
EVERY=${EVERY:-3}
STATE=$HOME/.claude/state/vault-capture

input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = true ] && exit 0
session=$(printf '%s' "$input" | jq -r '.session_id // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
[ -n "$session" ] && [ -r "$transcript" ] || exit 0

# Typed user messages only, since tool results also arrive as type user.
said=$(jq -c 'select(.type == "user" and (.message.content | type) == "string")' "$transcript" 2>/dev/null | wc -l)
head=$(git -C "$VAULT" rev-parse HEAD 2>/dev/null) || exit 0

mkdir -p "$STATE"
mark="$STATE/$session"
read -r last_said last_head 2>/dev/null < "$mark" || { last_said=0; last_head=$head; }

if [ "$head" != "$last_head" ] || [ $((said - last_said)) -lt "$EVERY" ]; then
    [ "$head" != "$last_head" ] && echo "$said $head" > "$mark"
    exit 0
fi
echo "$said $head" > "$mark"

jq -n '{decision: "block", reason: "Before stopping, capture what this session has talked about and done since the vault was last committed, following the vault contract in ~/code/memory/CLAUDE.md: the journal entry, any note it changes or creates, and the index, then commit. Personal and non-engineering talk counts. If there is truly nothing new, stop without writing anything."}'

#!/bin/sh
#
# vault-claude.sh NAME PROMPT [DIR]
#
# The headless claude every background vault job runs. It's sonnet on the
# claude.ai login, loads no settings so none of our hooks fire inside it, and
# keeps no transcript so the sweep never reads its own runs back. DIR is an
# extra directory it may read. Whatever it changed is committed once it exits,
# and one line per run goes to the log.

VAULT=${VAULT:-$HOME/code/memory}
LOG=$HOME/.claude/state/vault-scribe/runs.log
name=$1
prompt=$2
dir=${3:-$VAULT}

# Subscription usage only, never an API key that leaks in from somewhere.
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN

mkdir -p "$(dirname "$LOG")"
cd "$VAULT" || exit 1
# The transcript quotes text strangers wrote, so it gets no shell at all, reads
# only the vault and DIR, and can't write the files every session loads or
# anything git runs. dontAsk refuses whatever isn't listed here.
out=$(claude -p "$prompt" \
    --setting-sources "" \
    --model sonnet \
    --max-turns "${MAX_TURNS:-40}" \
    --tools Read,Edit,Write,Grep,Glob \
    --permission-mode dontAsk \
    --allowedTools "Read(/$VAULT/**)" "Read(/$dir/**)" "Edit(/$VAULT/**)" "Write(/$VAULT/**)" \
    --disallowedTools "Edit(/$VAULT/.git/**)" "Write(/$VAULT/.git/**)" \
        "Edit(/$VAULT/workspace.md)" "Write(/$VAULT/workspace.md)" \
        "Edit(/$VAULT/client.md)" "Write(/$VAULT/client.md)" \
        "Edit(/$VAULT/CLAUDE.md)" "Write(/$VAULT/CLAUDE.md)" \
    --no-session-persistence \
    --output-format json \
    --add-dir "$dir" 2>&1)
status=$?

summary=$(printf '%s' "$out" | jq -c '{turns: .num_turns, error: .is_error, in: .usage.input_tokens, cached: .usage.cache_read_input_tokens, out: .usage.output_tokens}' 2>/dev/null) ||
    summary=$(printf '%s' "$out" | tail -c 300 | tr '\n' ' ')
printf '%s %s exit=%s %s\n' "$(date -Is)" "$name" "$status" "$summary" >> "$LOG"

# The commit is made here, since claude has no git. Its last "memory: ..." line
# is the subject, cut down to plain characters.
if [ -n "$(git -C "$VAULT" status --porcelain)" ]; then
    subject=$(printf '%s' "$out" | jq -r '.result // empty' 2>/dev/null | grep '^memory: ' | tail -n 1 | tr -cd 'A-Za-z0-9 :,.()/_-' | cut -c1-72)
    git -C "$VAULT" add -A && git -C "$VAULT" commit -q -m "${subject:-memory: $name}"
fi
exit "$status"

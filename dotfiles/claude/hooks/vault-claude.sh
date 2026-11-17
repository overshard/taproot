#!/bin/sh
#
# vault-claude.sh NAME PROMPT [DIR]
#
# The headless claude every background vault job runs. It's sonnet on the
# claude.ai login, loads no settings so none of our hooks fire inside it, and
# keeps no transcript so the sweep never reads its own runs back. DIR is an
# extra directory it may read. One line per run goes to the log.

VAULT=${VAULT:-$HOME/code/memory}
LOG=$HOME/.claude/state/vault-scribe/runs.log
name=$1
prompt=$2
dir=${3:-$VAULT}

# Subscription usage only, never an API key that leaks in from somewhere.
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN

mkdir -p "$(dirname "$LOG")"
cd "$VAULT" || exit 1
out=$(claude -p "$prompt" \
    --setting-sources "" \
    --model sonnet \
    --max-turns "${MAX_TURNS:-40}" \
    --tools Read,Edit,Write,Bash,Grep,Glob \
    --permission-mode auto \
    --no-session-persistence \
    --output-format json \
    --add-dir "$dir" 2>&1)
status=$?

summary=$(printf '%s' "$out" | jq -c '{turns: .num_turns, error: .is_error, in: .usage.input_tokens, cached: .usage.cache_read_input_tokens, out: .usage.output_tokens}' 2>/dev/null) ||
    summary=$(printf '%s' "$out" | tail -c 300 | tr '\n' ' ')
printf '%s %s exit=%s %s\n' "$(date -Is)" "$name" "$status" "$summary" >> "$LOG"
exit "$status"

#!/bin/sh
#
# vault-sweep.sh
#
# The nightly backstop to vault-capture. The VPS host's vault-sweep.timer runs
# it in the claude container, and it hands Claude a plain text copy of every
# session touched in the last day and asks it to record whatever the vault is
# still missing.

set -eu

VAULT=${VAULT:-$HOME/code/memory}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

# User and assistant text only, since tool output is most of a transcript and
# none of it is what was said.
find "$HOME/.claude/projects" -name '*.jsonl' -mtime -1 | while read -r f; do
    jq -r 'select(.type == "user" or .type == "assistant")
        | (.message.content | if type == "string" then . else map(select(.type == "text") | .text) | join("\n") end) as $t
        | select($t != "") | "\(.type): \($t)"' "$f" 2>/dev/null > "$out/$(basename "$f" .jsonl).txt" || true
done
find "$out" -empty -delete
[ -n "$(ls "$out")" ] || exit 0

cd "$VAULT"
claude -p --permission-mode auto --add-dir "$out" \
"Nightly vault sweep. $out holds a text copy of every Claude session from the last day. Read them, compare with the vault (today's and yesterday's journal and the notes they touch), and record anything said or done that the vault doesn't have yet, following ~/code/memory/CLAUDE.md, then commit. Personal and non-engineering talk counts. Don't rewrite what's already there. If nothing is missing, change nothing."

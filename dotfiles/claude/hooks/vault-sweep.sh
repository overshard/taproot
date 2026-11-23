#!/bin/sh
#
# vault-sweep.sh
#
# The nightly vault job, run by vault-sweep.timer on the VPS host through
# docker exec. First it runs the scribe over every session from the last two
# days, which only reads what no earlier scribe run has, then it has Claude
# tidy up the notes that changed in the last day.

VAULT=${VAULT:-$HOME/code/memory}
STATE=$HOME/.claude/state/vault-scribe
MAX_WORDS=${MAX_WORDS:-8000}
here=$(dirname "$0")
export TZ=America/New_York

find "$HOME/.claude/projects" -maxdepth 2 -name '*.jsonl' -mtime -2 | while read -r f; do
    "$here/vault-scribe.sh" "$f"
done

mkdir -p "$STATE"
exec 9>"$STATE/lock"
flock -w 900 9 || exit 1

# Only notes changed since the last tidy, so a run never redoes the one before.
last=$(cat "$STATE/sweep-head" 2>/dev/null)
range=${last:+$last..HEAD}
changed=$(git -C "$VAULT" log ${range:---since=yesterday} --name-only --format= -- projects topics decisions people open.md | sort -u | tr '\n' ' ')
[ -n "$changed" ] || exit 0
big=$(cd "$VAULT" && for f in projects/*.md topics/*.md decisions/*.md people/*.md; do
    w=$(wc -w < "$f")
    [ "$w" -gt "$MAX_WORDS" ] && echo "$f ($w words)"
done | tr '\n' ' ')

MAX_TURNS=60 "$here/vault-claude.sh" sweep "Nightly vault tidy in $VAULT, following $VAULT/CLAUDE.md and the Writing section of $VAULT/workspace.md. These notes changed since the last tidy: $changed. For each, read it alongside the last two days of journal and fix it so it reads as the current state: drop facts a later entry made false, fold duplicate lines together, and move Open items the journal has since closed out of the note's open threads. Never change what a journal file already says, only append to it. Read open.md against the last two days of journal and remove anything done, dropped or answered, so it lists only what's still outstanding. Check index.md and the section indexes it points to have a line for every note that changed and that each hook is still true. Notes over $MAX_WORDS words: ${big:-none}. Don't split them, add one line for each under Open in today's journal so Isaac can decide. Don't commit, that happens after you finish. End your reply with the line memory: nightly tidy. If nothing needs changing, change nothing." &&
    git -C "$VAULT" rev-parse HEAD > "$STATE/sweep-head"

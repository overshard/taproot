#!/bin/sh
#
# vault-digest.sh
#
# A SessionStart hook for the VPS. Puts the newest Open lines from the vault's
# journal in front of Claude so a new session knows what's in flight without
# reading the whole index first.

VAULT=${VAULT:-$HOME/code/memory}
LINES=${LINES:-25}

latest=$(ls "$VAULT"/journal/2*.md 2>/dev/null | tail -n 2)
[ -n "$latest" ] || exit 0

open=$(awk '
    /^## /         { title = substr($0, 4) }
    /^\*\*Open\*\*/ { inopen = 1; next }
    /^\*\*|^## /   { inopen = 0 }
    inopen && /^- / { print "- (" title ") " substr($0, 3) }
' $latest | tail -n "$LINES")
[ -n "$open" ] || exit 0

jq -n --arg open "$open" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ("Newest Open lines from the vault journal, for context only. index.md and the notes have the rest.\n" + $open)}}'

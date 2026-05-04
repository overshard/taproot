#!/bin/sh
#
# sync.sh
#
# Pull latest from origin for every git repo under ~/code/. Skips repos with
# uncommitted changes. Uses --ff-only so divergent branches never get a silent
# merge or rebase; they just warn and move on.
#
# Run after switching machines (e.g. desktop -> laptop) to catch up.
#

set -u

CODE="$HOME/code"
if [ ! -d "$CODE" ]; then
    echo "ERROR: $CODE does not exist" >&2
    exit 1
fi

ok=0
warn=0
skip=0

for path in "$CODE"/*/; do
    [ -d "$path/.git" ] || continue
    name=$(basename "$path")

    cd "$path"

    if [ -n "$(git status --porcelain)" ]; then
        printf "  [skip] %s (dirty)\n" "$name"
        skip=$((skip + 1))
        continue
    fi

    if ! git symbolic-ref --quiet HEAD >/dev/null; then
        printf "  [skip] %s (detached HEAD)\n" "$name"
        skip=$((skip + 1))
        continue
    fi

    if ! git fetch --all --prune --quiet 2>/dev/null; then
        printf "  [warn] %s (fetch failed)\n" "$name"
        warn=$((warn + 1))
        continue
    fi

    before=$(git rev-parse HEAD)

    if git pull --ff-only --quiet 2>/dev/null; then
        after=$(git rev-parse HEAD)
        if [ "$before" = "$after" ]; then
            printf "  [ok]   %s (up to date)\n" "$name"
        else
            printf "  [ok]   %s (%s -> %s)\n" "$name" \
                "$(git rev-parse --short "$before")" \
                "$(git rev-parse --short "$after")"
        fi
        ok=$((ok + 1))
    else
        printf "  [warn] %s (not fast-forward; manual pull/rebase needed)\n" "$name"
        warn=$((warn + 1))
    fi
done

echo ""
printf "%d updated, %d warned, %d skipped\n" "$ok" "$warn" "$skip"

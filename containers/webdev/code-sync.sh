#!/bin/sh
#
# code-sync.sh
#
# Two-pass sync for the ~/code/ workspace.
#
# 1) Pull latest from origin for every git repo already under ~/code/. Skips
#    repos with uncommitted changes or detached HEAD. Uses --ff-only so a
#    divergent branch never gets a silent merge or rebase.
#
# 2) Hit the public GitHub API for $GITHUB_USER (overshard) and clone any
#    non-archived, non-fork, owned repos that don't exist locally yet, using
#    the SSH key configured globally in ~/.ssh/config (no auth needed for the
#    API call; this is one request per run, well under the 60/hr unauth
#    rate limit).
#
# Run after switching machines (e.g. desktop -> laptop) to catch up.
#

set -u

CODE="$HOME/code"
GITHUB_USER="overshard"

if [ ! -d "$CODE" ]; then
    echo "ERROR: $CODE does not exist" >&2
    exit 1
fi

ok=0
warn=0
skip=0
new=0

echo "Pulling existing repos..."

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

cd "$CODE"

echo ""
echo "Discovering repos for $GITHUB_USER..."

api="https://api.github.com/users/$GITHUB_USER/repos?per_page=100&type=owner"
json=$(curl -fsSL -H 'Accept: application/vnd.github+json' "$api" 2>/dev/null || true)

if [ -z "$json" ]; then
    printf "  [warn] GitHub API request failed\n"
    warn=$((warn + 1))
else
    count=$(printf '%s' "$json" | jq 'length' 2>/dev/null || echo 0)
    if [ "$count" -eq 100 ]; then
        printf "  [warn] received exactly 100 repos; pagination may be needed\n"
        warn=$((warn + 1))
    fi

    list=$(mktemp)
    printf '%s' "$json" \
        | jq -r '.[] | select(.archived == false and .fork == false) | "\(.name) \(.ssh_url)"' \
        > "$list"

    while IFS=' ' read -r repo url; do
        [ -z "$repo" ] && continue
        [ -d "$CODE/$repo" ] && continue
        printf "  [new]  cloning %s\n" "$repo"
        if git clone --quiet "$url" "$CODE/$repo" 2>/dev/null; then
            new=$((new + 1))
        else
            printf "  [warn] clone failed for %s\n" "$repo"
            warn=$((warn + 1))
        fi
    done < "$list"
    rm -f "$list"
fi

echo ""
printf "%d updated, %d cloned, %d warned, %d skipped\n" "$ok" "$new" "$warn" "$skip"

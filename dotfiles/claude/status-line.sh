#!/bin/bash
# Claude Code status line. Requires bash, jq, git and date.
#
#   usg ▓▓▓▓▓░░░░░ 52% · resets 2h 14m | ctx ▓▓░░░░░░░░ 18% | ~/code/finance  main | 3:45 PM ET
#
# Reads the status-line JSON on stdin. Every optional field uses `// empty`, so
# missing data degrades instead of erroring: context_window only appears once a
# turn has run, and rate_limits is Pro/Max only, after the first API response.

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd="$PWD"

YELLOW=$'\033[93m'
GREEN=$'\033[92m'
BLUE=$'\033[96m'
RED=$'\033[91m'
DIM=$'\033[90m'
RESET=$'\033[0m'

make_bar() {  # <int-pct> -> a 10-cell ▓/░ bar, one filled cell per 10%
    local p="$1" filled empty i out=""
    [ "$p" -lt 0 ] && p=0
    filled=$(( p / 10 )); [ "$filled" -gt 10 ] && filled=10
    empty=$(( 10 - filled ))
    i=0; while [ $i -lt $filled ]; do out="${out}▓"; i=$(( i + 1 )); done
    i=0; while [ $i -lt $empty ]; do out="${out}░"; i=$(( i + 1 )); done
    printf '%s' "$out"
}
sev_color() {  # <int-pct> -> green under 50%, yellow under 80%, red above
    local p="$1"
    if   [ "$p" -ge 80 ]; then printf '%s' "$RED"
    elif [ "$p" -ge 50 ]; then printf '%s' "$YELLOW"
    else printf '%s' "$GREEN"; fi
}

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ]; then
    pct_int=$(printf "%.0f" "$used_pct")
    context_part="${DIM}ctx${RESET} ${YELLOW}$(make_bar "$pct_int") ${pct_int}%${RESET}"
else
    context_part="${DIM}ctx${RESET} ${YELLOW}░░░░░░░░░░ 0%${RESET}"
fi

display_dir=$(echo "$cwd" | sed "s|^$HOME|~|")

# -c core.fsmonitor= skips the optional fsmonitor lock, so the status line
# never contends with a git operation already running in that repo.
branch_part=""
if git -C "$cwd" -c core.fsmonitor= rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$cwd" -c core.fsmonitor= symbolic-ref --short HEAD 2>/dev/null \
             || git -C "$cwd" -c core.fsmonitor= rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        branch_icon='⎇'  # U+2387, which renders without a Nerd Font
        branch_part=" ${BLUE}${branch_icon} ${branch}${RESET}"
    fi
fi

# The 5-hour rate-limit usage, the same number /usage reports.
quota_part=""
h5=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$h5" ]; then
    h5_int=$(printf '%.0f' "$h5")
    qc=$(sev_color "$h5_int")
    quota_part="${DIM}usg${RESET} ${qc}$(make_bar "$h5_int") ${h5_int}%${RESET}"
    # resets_at is Unix epoch seconds.
    reset_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    if [ -n "$reset_at" ]; then
        left=$(( reset_at - $(date +%s) ))
        [ "$left" -lt 0 ] && left=0
        h=$(( left / 3600 )); m=$(( (left % 3600) / 60 ))
        if [ "$h" -gt 0 ]; then eta="${h}h ${m}m"; else eta="${m}m"; fi
        quota_part="${quota_part} ${DIM}· resets ${eta}${RESET}"
    fi
fi

# Forced to Eastern whatever the system clock is, and America/New_York tracks
# EST and EDT on its own.
clock=$(TZ="America/New_York" date '+%-I:%M %p')

dir_part="${GREEN}${display_dir}${RESET}${branch_part}"
SEP=" ${DIM}|${RESET} "
line="${context_part}${SEP}${dir_part}${SEP}${clock} ET"
[ -n "$quota_part" ] && line="${quota_part}${SEP}${line}"
echo "$line"

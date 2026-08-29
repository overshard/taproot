#!/bin/sh
#
# restic-setup.sh
#
# Check the restic credentials in ~/.restic, and walk through entering them if
# they are missing or wrong. This exists so that setting up backups on a fresh
# container is one command that tells you what it wants, rather than opening
# two files in nvim and hoping the shape is right.
#
#   restic-setup            check, then offer to fix whatever is wrong
#   restic-setup --check    check only, quietly; exit 0 if backups will work
#
# The files it manages, all in the bythewood-restic volume:
#
#   ~/.restic/b2-env           B2_ACCOUNT_ID, B2_ACCOUNT_KEY, RESTIC_HOST
#   ~/.restic/password         password for the webdev repo
#   ~/.restic/alpine-password  password for the old server's repo (optional)
#
# --check is what `make doctor` in taproot calls, so keep it silent and keep
# its exit code meaningful.

set -eu

RESTIC_DIR="$HOME/.restic"
B2_ENV="$RESTIC_DIR/b2-env"
PW_FILE="$RESTIC_DIR/password"
ALPINE_PW_FILE="$RESTIC_DIR/alpine-password"
REPO="b2:overshard-backups:webdev"

CHECK_ONLY=no
case "${1:-}" in
--check) CHECK_ONLY=yes ;;
--help|-h) sed -n '2,22p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit 0 ;;
"") ;;
*) echo "unknown option: $1" >&2; sed -n '2,22p' "$0" | sed 's/^#[[:space:]]\{0,1\}//' >&2; exit 2 ;;
esac

# ---------------------------------------------------------------- inspection

# Everything below reads the current state without changing it, so the check
# path and the interactive path agree on what is wrong.
B2_ID=""
B2_KEY=""
HOSTTAG=""
if [ -f "$B2_ENV" ]; then
    # A subshell, so a malformed b2-env cannot leak variables or a `set -e`
    # failure into this script.
    eval "$(
        . "$B2_ENV" >/dev/null 2>&1 || true
        printf 'B2_ID=%s\n'   "$(printf '%s' "${B2_ACCOUNT_ID:-}"  | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"
        printf 'B2_KEY=%s\n'  "$(printf '%s' "${B2_ACCOUNT_KEY:-}" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"
        printf 'HOSTTAG=%s\n' "$(printf '%s' "${RESTIC_HOST:-}"    | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/")"
    )"
fi

have_all_fields() {
    [ -n "$B2_ID" ] && [ -n "$B2_KEY" ] && [ -n "$HOSTTAG" ] && [ -s "$PW_FILE" ]
}

# The only check that actually proves anything: open the repository. Wrong key,
# wrong password and no network all land here rather than being guessed at from
# the shape of the files.
#
# Wrapped in a timeout because restic retries a failing backend about ten times
# with backoff, so a revoked key takes minutes to come back rather than
# seconds. `make doctor` calls this, and a doctor that hangs is worse than one
# that is unsure. 124 is the timeout's own exit code.
RESTIC_TIMEOUT=${RESTIC_TIMEOUT:-30}
restic_probe() {
    B2_ACCOUNT_ID="$B2_ID" B2_ACCOUNT_KEY="$B2_KEY" \
    RESTIC_REPOSITORY="$REPO" RESTIC_PASSWORD_FILE="$PW_FILE" \
        timeout "$RESTIC_TIMEOUT" restic cat config "$@"
}

repo_opens() {
    restic_probe >/dev/null 2>&1
}

if [ "$CHECK_ONLY" = yes ]; then
    have_all_fields || exit 1
    repo_opens || exit 1
    exit 0
fi

# ------------------------------------------------------------------- report

mask() {
    v=$1
    n=$(printf '%s' "$v" | wc -c)
    if   [ -z "$v" ];    then printf 'not set'
    elif [ "$n" -le 8 ]; then printf '********'
    else printf '%s...%s' "$(printf '%s' "$v" | cut -c1-4)" "$(printf '%s' "$v" | cut -c$((n-1))-)"
    fi
}

echo "restic credentials in $RESTIC_DIR"
echo ""
printf '  %-18s %s\n' "B2_ACCOUNT_ID"  "$(mask "$B2_ID")"
printf '  %-18s %s\n' "B2_ACCOUNT_KEY" "$(mask "$B2_KEY")"
printf '  %-18s %s\n' "RESTIC_HOST"    "${HOSTTAG:-not set}"
printf '  %-18s %s\n' "repo password"  "$([ -s "$PW_FILE" ] && echo set || echo 'not set')"
printf '  %-18s %s\n' "alpine password" "$([ -s "$ALPINE_PW_FILE" ] && echo set || echo 'not set, optional')"
echo ""

if have_all_fields; then
    printf 'opening %s ... ' "$REPO"
    if repo_opens; then
        echo "ok"
        echo ""
        echo "backups are working. nothing to do here."
        echo ""
        echo "  restic-backup    take a snapshot from this machine"
        echo "  restic-status    last snapshot per host, both repos"
        exit 0
    fi
    echo "FAILED"
    echo ""
    echo "the files are filled in but the repository will not open. that is"
    echo "usually a revoked or mistyped B2 key, a wrong repo password, or no"
    echo "network. entering them again is the fastest way to find out which."
else
    echo "something is missing, so backups will not run yet."
fi

echo ""

if [ ! -t 0 ]; then
    echo "this needs a terminal to read the values. run it as:" >&2
    echo "" >&2
    echo "  docker exec -it bythewood-webdev restic-setup" >&2
    exit 1
fi

# ------------------------------------------------------------------ where from

cat <<'GUIDE'
------------------------------------------------------------------------
where these come from

  Everything is in 1Password first. Look for the Backblaze B2 item (the
  application key) and the restic repository password. If both are there,
  paste them below and you are done.

  If you need a NEW B2 application key, at https://secure.backblaze.com

    1. Buckets. There should be a private bucket named overshard-backups.
       Create it if it is gone: private, no encryption, no object lock.
       Restic does its own encryption, and object lock would break prune.

    2. Application Keys, then "Add a New Application Key".
         name         anything, e.g. webdev-desktop
         bucket       overshard-backups, not "All"
         access       Read and Write
         leave the file-name prefix and duration empty

    3. Save it. The keyID and the applicationKey are shown ONCE. The
       keyID is B2_ACCOUNT_ID, the applicationKey is B2_ACCOUNT_KEY.
       Put both back into 1Password before you close the page.

  The repo password is NOT recoverable. If it is lost, the snapshots in
  that repository are lost with it, and the only fix is a new repository.
------------------------------------------------------------------------
GUIDE
echo ""

# --------------------------------------------------------------- collecting

# Enter keeps whatever is already there, so this is safe to re-run to change
# one field without retyping the rest.
#
# These set a global rather than printing a value for $(...) to capture. Run
# inside a command substitution the prompt is captured too, so the terminal
# shows nothing and you are typing blind into what looks like a hung script.
ANSWER=""

ask() {
    printf '%s' "$1"
    [ -n "$2" ] && printf ' [enter keeps %s]' "$(mask "$2")"
    printf ': '
    read -r ANSWER || ANSWER=""
    [ -n "$ANSWER" ] || ANSWER=$2
}

ask_secret() {
    printf '%s' "$1"
    [ -n "$2" ] && printf ' [enter keeps it]'
    printf ': '
    stty -echo 2>/dev/null || true
    read -r ANSWER || ANSWER=""
    stty echo 2>/dev/null || true
    printf '\n'
    [ -n "$ANSWER" ] || ANSWER=$2
}

ask        "B2 keyID"          "$B2_ID";  NEW_ID=$ANSWER
ask_secret "B2 applicationKey" "$B2_KEY"; NEW_KEY=$ANSWER

# The tag that separates this machine's snapshots from the other one's.
# Retention is applied per host, so a typo here quietly gives a third machine
# its own 7/4/6 window and stops pruning the real one.
while :; do
    ask "this machine, desktop or laptop" "$HOSTTAG"
    NEW_HOST=$ANSWER
    case "$NEW_HOST" in
    desktop|laptop) break ;;
    "") echo "  nothing entered, and nothing to keep" ;;
    *)  echo "  must be exactly 'desktop' or 'laptop'" ;;
    esac
done

CURRENT_PW=""
[ -s "$PW_FILE" ] && CURRENT_PW=$(cat "$PW_FILE")
ask_secret "restic repository password" "$CURRENT_PW"; NEW_PW=$ANSWER

if [ -z "$NEW_ID" ] || [ -z "$NEW_KEY" ] || [ -z "$NEW_PW" ]; then
    echo "" >&2
    echo "one of the values is empty. nothing was written." >&2
    exit 1
fi

# ------------------------------------------------------------------ writing

# Written to a temp file and moved into place, so an interrupted run cannot
# leave a half-written credentials file behind.
mkdir -p "$RESTIC_DIR"
chmod 700 "$RESTIC_DIR"

umask 077

tmp="$B2_ENV.tmp.$$"
cat > "$tmp" <<ENV
# Written by restic-setup. Sourced by restic-backup, restic-restore and
# restic-status. RESTIC_HOST is the snapshot tag that keeps this machine's
# retention window separate from the other one's.
export B2_ACCOUNT_ID="$NEW_ID"
export B2_ACCOUNT_KEY="$NEW_KEY"
export RESTIC_HOST="$NEW_HOST"
ENV
chmod 600 "$tmp"
mv "$tmp" "$B2_ENV"

tmp="$PW_FILE.tmp.$$"
printf '%s' "$NEW_PW" > "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$PW_FILE"

echo ""
echo "wrote $B2_ENV and $PW_FILE (0600)"
echo ""

# -------------------------------------------------------------- verification

B2_ID=$NEW_ID
B2_KEY=$NEW_KEY
HOSTTAG=$NEW_HOST

printf 'opening %s ... ' "$REPO"
if repo_opens; then
    echo "ok"
    echo ""
    echo "backups are set up. next:"
    echo ""
    echo "  restic-backup     take a snapshot from this machine"
    echo "  restic-restore    pull everything back, on a fresh container"
    echo "  restic-status     last snapshot per host, both repos"
    exit 0
fi

echo "FAILED"
echo ""
echo "the credentials are saved but the repository did not open. in order of"
echo "how often it is the cause:"
echo ""
echo "  the applicationKey is wrong, or was revoked in the B2 console"
echo "  the key is not scoped to the overshard-backups bucket"
echo "  the repo password is wrong"
echo "  no network out of this container"
echo ""
echo "(it gives up after ${RESTIC_TIMEOUT}s. set RESTIC_TIMEOUT to wait longer.)"
echo ""
echo "the raw error, which usually names one of those:"
echo ""
restic_probe 2>&1 | sed 's/^/  /' | head -20 || true
echo ""
echo "if this is a brand new bucket with no repository in it yet, that is"
echo "expected: restic-backup runs 'restic init' on its first run."
exit 1

#!/bin/sh
#
# webdev-exec.sh
#
# Run a build tool inside the webdev container against this same source tree.
#
# aiagent has no toolchain: it runs an agent, it does not build. But an agent
# that cannot compile what it wrote cannot tell working code from code that
# merely parses, and a 9B model will not reliably reach for a two-step
# `docker exec` incantation on its own. So the incantation lives here instead,
# symlinked to `go`, `gofmt` and `bun` on PATH. The agent types `go build ./...`
# and never learns that another container was involved.
#
# Both containers mount bythewood-code and both run as UID 1001, so the file
# webdev writes is the file aiagent reads. Only the mount point differs, which
# is the one thing this script has to translate.
#
# Invoked by its own name it takes the command as the first argument:
#     webdev-exec make check
#

set -eu

CONTAINER=bythewood-webdev
AI_ROOT=/home/ai/code
DEV_ROOT=/home/dev/code

# Called through one of the symlinks, argv[0] is the tool. Called by any other
# name, the tool is the first argument: `webdev-exec make check`. Matching the
# symlink names rather than this script's own name means renaming the script
# cannot silently turn every invocation into a wrong one.
cmd=$(basename "$0")
case "$cmd" in
    go|gofmt|bun) ;;
    *)
        if [ $# -eq 0 ]; then
            echo "usage: webdev-exec <command> [args...]" >&2
            exit 2
        fi
        cmd=$1
        shift ;;
esac

# Checked separately rather than by letting `docker exec` fail, so that a real
# compile error is never reported as a missing container. The agent acts on
# these messages, so they say what to do rather than what went wrong.
state=$(sudo docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo missing)
if [ "$state" != "true" ]; then
    echo "webdev-exec: cannot run '$cmd': the $CONTAINER container is not running." >&2
    echo "webdev-exec: this container has no toolchain of its own; it borrows webdev's." >&2
    echo "webdev-exec: ask the human to start it (\`make up\` from a taproot" >&2
    echo "webdev-exec: clone, or \`docker start $CONTAINER\`), or carry on with" >&2
    echo "webdev-exec: work that does not need to build. Do not claim the code builds." >&2
    exit 127
fi

# The shared volume is the only path both containers can see. Anything outside
# it exists in this container alone and webdev would silently build the wrong
# tree, or nothing at all.
dir=$(pwd)
case "$dir" in
    "$AI_ROOT"|"$AI_ROOT"/*) dir="$DEV_ROOT${dir#$AI_ROOT}" ;;
    *)
        echo "webdev-exec: cannot run '$cmd' from $dir." >&2
        echo "webdev-exec: only $AI_ROOT and below is shared with webdev. cd there first." >&2
        exit 127 ;;
esac

# No --tty on purpose: without one, tools emit plain text instead of progress
# bars and cursor escapes, which is what should land in the agent's context.
# The exec inherits the image's ENV, so Go and bun are already on PATH there.
exec sudo docker exec --workdir "$dir" --user dev "$CONTAINER" "$cmd" "$@"

#!/bin/sh
#
# restic-check.sh
#
# Read back a random 5% of the repository and check its structure. Run weekly
# by the host's restic-check.timer, or by hand with make verify. A full
# read of every pack would download the whole repo from B2 each time.
#

set -eu

. "$HOME/.restic/b2-env"
export RESTIC_REPOSITORY="b2:overshard-backups:webdev"
export RESTIC_PASSWORD_FILE="$HOME/.restic/password"

restic check --read-data-subset=5%

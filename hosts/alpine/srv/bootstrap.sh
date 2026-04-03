#!/bin/sh
#
# bootstrap.sh
#
# Clone every project into a fresh code directory and add server remotes.
# Run from the directory where you want your code to live:
#
#   cd ~/code
#   sh taproot/hosts/alpine/srv/bootstrap.sh
#
# Reads projects.conf for the manifest. Skips repos that already exist.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/projects.conf"
SERVER="root@bythewood.me"
CODE_DIR="$(pwd)"

if [ ! -f "$CONF" ]; then
    echo "Cannot find projects.conf at $CONF"
    exit 1
fi

echo "Bootstrapping code directory: $CODE_DIR"
echo ""

while IFS='|' read -r name port repo branch has_data has_migrate; do
    case "$name" in \#*|"") continue ;; esac

    if [ -d "$CODE_DIR/$name" ]; then
        echo "  $name — already exists, skipping clone"
    else
        echo "  $name — cloning from github"
        git clone "git@github.com:${repo}.git" "$CODE_DIR/$name" -b "$branch"
    fi

    # Add server remote if not already set
    cd "$CODE_DIR/$name"
    if git remote get-url server >/dev/null 2>&1; then
        echo "  $name — server remote already set"
    else
        git remote add server "${SERVER}:/srv/git/${name}.git"
        echo "  $name — added server remote"
    fi
    cd "$CODE_DIR"

    echo ""
done < "$CONF"

echo "Done. Push to deploy:  git push server master"

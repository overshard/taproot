#!/bin/sh
#
# quickstart.sh
#
# Alpine Linux host provisioning. Run once on a fresh server.
# Push the entire hosts/alpine/ directory via scp first:
#
#   scp -r hosts/alpine/ root@your-server:/root/alpine
#   ssh root@your-server "cd /root/alpine && sh quickstart.sh"
#

set -e

# Install dependencies
apk update
apk upgrade
apk add \
    neovim \
    curl \
    rsync \
    git \
    ip6tables \
    iptables \
    ufw \
    borgbackup \
    docker \
    docker-compose \
    caddy

# Configure firewall
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 80/udp   # http3
ufw allow 443/tcp
ufw allow 443/udp  # http3
ufw --force enable

# Install configuration files
cp etc/apk/repositories /etc/apk/repositories && chmod 644 /etc/apk/repositories
cp etc/periodic/daily/apk-autoupgrade /etc/periodic/daily/apk-autoupgrade && chmod 700 /etc/periodic/daily/apk-autoupgrade
cp etc/periodic/daily/borg-autobackup /etc/periodic/daily/borg-autobackup && chmod 700 /etc/periodic/daily/borg-autobackup
cp etc/docker/daemon.json /etc/docker/daemon.json && chmod 644 /etc/docker/daemon.json
cp etc/caddy/Caddyfile /etc/caddy/Caddyfile && chmod 644 /etc/caddy/Caddyfile
cp root/server-health-check.sh /root/server-health-check.sh && chmod 700 /root/server-health-check.sh

# Create directory structure
mkdir -p /srv/git /srv/docker /srv/data /srv/backup

# Initialize borg backup repository
borg init -e none /srv/backup

# Provision each project from projects.conf
while IFS='|' read -r name port repo branch has_data has_migrate; do
    # Skip comments and blank lines
    case "$name" in \#*|"") continue ;; esac

    echo "--- Provisioning $name on port $port ---"

    # Bare git repo for push-to-deploy
    if [ ! -d "/srv/git/${name}.git" ]; then
        git init --bare "/srv/git/${name}.git"
    fi

    # Working clone for docker-compose
    if [ ! -d "/srv/docker/${name}" ]; then
        git clone "git@github.com:${repo}.git" "/srv/docker/${name}" -b "$branch"
    fi

    # Data directory
    if [ "$has_data" = "yes" ] && [ ! -d "/srv/data/${name}" ]; then
        mkdir -p "/srv/data/${name}"
    fi

    # .env file from sample if it exists
    if [ ! -f "/srv/docker/${name}/.env" ] && [ -f "/srv/docker/${name}/samplefiles/env.sample" ]; then
        cp "/srv/docker/${name}/samplefiles/env.sample" "/srv/docker/${name}/.env"
        echo "  ** Review and edit /srv/docker/${name}/.env **"
    fi

    # Post-receive hook
    cat > "/srv/git/${name}.git/hooks/post-receive" << HOOK
#!/bin/sh

while read oldrev newrev ref; do
  if [ "\$ref" = "refs/heads/${branch}" ]; then
    unset GIT_DIR
    START_TIME=\$(date +%s)
    cd /srv/docker/${name}
    git pull
    docker compose up --build --detach
HOOK

    if [ "$has_migrate" = "yes" ]; then
        cat >> "/srv/git/${name}.git/hooks/post-receive" << 'MIGRATE'
    docker compose run --rm web python3 manage.py migrate --noinput
MIGRATE
    fi

    cat >> "/srv/git/${name}.git/hooks/post-receive" << TAIL
    docker system prune --force
    END_TIME=\$(date +%s)
    echo "Total build time: \$((END_TIME - START_TIME))s"
  fi
done
TAIL

    chmod +x "/srv/git/${name}.git/hooks/post-receive"

done < srv/projects.conf

# Start services and add to startup
rc-update add ufw boot && rc-service ufw start
rc-update add docker boot && rc-service docker start
rc-update add caddy boot && rc-service caddy start

echo ""
echo "Server provisioned. Review .env files in /srv/docker/*/  before starting containers."
echo "Add server remotes to your local repos:  git remote add server root@this-server:/srv/git/PROJECT.git"

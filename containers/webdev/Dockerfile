# webdev
#
# Used for working on most of my website development projects, using a rolling
# distro to have the latest packages to work with. Uses tmux, neovim, and
# claude code for a full TUI workflow.
#
# NOTE: Build from the taproot repo root so dotfiles are in the build context:
#     docker build --tag overshard/webdev:latest -f containers/webdev/Dockerfile .
#
# Create volumes:
#     docker volume create --name bythewood-code
#     docker volume create --name bythewood-claude
#     docker volume create --name bythewood-ssh
#
# Start container:
#     docker run --detach --restart unless-stopped --name bythewood-webdev \
#         --volume bythewood-code:/home/dev/code \
#         --volume bythewood-claude:/home/dev/.claude \
#         --volume bythewood-ssh:/home/dev/.ssh \
#         --volume /var/run/docker.sock:/var/run/docker.sock \
#         -p 8000:8000 \
#         overshard/webdev:latest
#
# Copy SSH keys into the volume (first time only, PowerShell):
#     docker cp $HOME/.ssh/home_key bythewood-webdev:/home/dev/.ssh/home_key
#     docker cp $HOME/.ssh/home_key.pub bythewood-webdev:/home/dev/.ssh/home_key.pub
#     docker exec bythewood-webdev sudo chown dev:dev /home/dev/.ssh/home_key /home/dev/.ssh/home_key.pub
#     docker exec bythewood-webdev chmod 600 /home/dev/.ssh/home_key
#
# Connect:
#     docker exec -it bythewood-webdev tmux
#
# I use volumes for code, claude, and ssh to make rebuilds of the container
# easy without losing project files, claude auth/memory, or SSH keys. I have
# scripts setup on my hosts to rebuild images, delete old containers, and
# start the new containers when I make updates.
#
# NOTE: Fresh volumes will inherit correct dev:dev ownership from the image.
# Existing volumes retain their permissions. If you hit root:root ownership
# issues on existing volumes, fix with:
#     docker exec -it bythewood-webdev sudo chown -R dev:dev /home/dev/.claude /home/dev/code
#
# Docker is included in this build so I can test docker stuff inside my
# containers. Note that to get docker to function in a docker container you
# need to use the host's docker and provide the docker.sock file from the host
# to the container. This can be done with `--volume /var/run/docker.sock:/var/run/docker.sock`.
#
# The naming is so that I can make a container and volumes for each of my
# clients and keep a separation of work.


FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    PATH="/home/dev/.local/bin:$PATH"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # Dev tools
        curl git rsync neovim openssh-client tmux whois nmap \
        # System essentials
        tzdata ca-certificates sudo \
        # Build tools
        build-essential \
        # Monitoring
        htop \
        # Python
        python3 python3-pip python3-venv \
        # Database and caching
        postgresql redis-server \
        # Docker
        docker.io docker-compose-v2 \
        # Process management
        supervisor && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    mkdir -p /root/.local/share/corepack/shims && \
    corepack enable && \
    corepack prepare yarn@stable --activate && \
    rm -rf /var/lib/apt/lists/*

RUN printf '%s\n' \
    'bind 127.0.0.1' \
    'protected-mode yes' \
    'port 6379' \
    'supervised no' \
    'daemonize no' \
    'logfile ""' \
    'dir /var/lib/redis' \
    'save ""' \
    > /etc/redis/redis.conf && \
    mkdir -p /var/lib/redis && \
    chown redis:redis /var/lib/redis

RUN ln -snf /usr/share/zoneinfo/UTC /etc/localtime && echo "UTC" > /etc/timezone

RUN service postgresql start && \
    sudo -u postgres createuser -s dev && \
    service postgresql stop

RUN printf '%s\n' \
    '[supervisord]' \
    'pidfile=/run/supervisord.pid' \
    'user=root' \
    'nodaemon=true' \
    'logfile=/dev/null' \
    'logfile_maxbytes=0' \
    '' \
    '[program:postgresql]' \
    'command=/usr/lib/postgresql/16/bin/postgres -D /var/lib/postgresql/16/main -c config_file=/etc/postgresql/16/main/postgresql.conf' \
    'autostart=true' \
    'user=postgres' \
    'stdout_logfile=/dev/fd/1' \
    'stdout_logfile_maxbytes=0' \
    'redirect_stderr=true' \
    '' \
    '[program:redis]' \
    'command=/usr/bin/redis-server /etc/redis/redis.conf' \
    'autostart=true' \
    'user=redis' \
    'stdout_logfile=/dev/fd/1' \
    'stdout_logfile_maxbytes=0' \
    'redirect_stderr=true' \
    > /etc/supervisord.conf

RUN useradd -m -G sudo,docker,postgres,redis -s /bin/bash dev && \
    echo "dev ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/dev

COPY dotfiles/bash_aliases /home/dev/.bash_aliases
COPY dotfiles/gitconfig /home/dev/.gitconfig
COPY dotfiles/neovim/init.lua /home/dev/.config/nvim/init.lua
COPY dotfiles/tmux.conf /home/dev/.tmux.conf
RUN chown -R dev:dev /home/dev/.bash_aliases /home/dev/.gitconfig /home/dev/.config /home/dev/.tmux.conf && \
    echo "source ~/.bash_aliases" >> /home/dev/.bashrc

RUN mkdir -p /home/dev/code /home/dev/.claude /home/dev/.ssh && \
    printf '%s\n' \
    'Host *' \
    '  IdentityFile ~/.ssh/home_key' \
    '  IdentitiesOnly yes' \
    '  StrictHostKeyChecking accept-new' \
    '  UpdateHostKeys yes' \
    '  HashKnownHosts yes' \
    '  PasswordAuthentication no' \
    '  ServerAliveInterval 60' \
    '  ServerAliveCountMax 3' \
    '  VisualHostKey yes' \
    > /home/dev/.ssh/config && \
    chmod 700 /home/dev/.ssh && \
    chmod 600 /home/dev/.ssh/config && \
    chown -R dev:dev /home/dev/code /home/dev/.claude /home/dev/.ssh

WORKDIR /home/dev
USER dev

RUN curl -fsSL https://claude.ai/install.sh | bash

CMD ["sudo", "/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]

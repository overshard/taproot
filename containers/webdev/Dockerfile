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
#     docker volume create --name bythewood-restic
#
# Start container (--init gives us a proper PID 1 that reaps zombies — without
# it, exiting tmux leaves [tmux: server] <defunct> entries hanging around):
#     docker run --detach --init --restart unless-stopped --name bythewood-webdev \
#         --volume bythewood-code:/home/dev/code \
#         --volume bythewood-claude:/home/dev/.claude \
#         --volume bythewood-ssh:/home/dev/.ssh \
#         --volume bythewood-restic:/home/dev/.restic \
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
# Restic credentials (first time only) — pull from 1Password:
#     docker exec -i bythewood-webdev tee /home/dev/.restic/password > /dev/null  # paste, Ctrl-D
#     docker exec -i bythewood-webdev tee /home/dev/.restic/b2-env > /dev/null    # paste, Ctrl-D
#     docker exec bythewood-webdev chmod 600 /home/dev/.restic/password /home/dev/.restic/b2-env
#
# b2-env contents:
#     export B2_ACCOUNT_ID="<keyID from 1Password>"
#     export B2_ACCOUNT_KEY="<applicationKey from 1Password>"
#
# Backup and restore:
#     docker exec -it bythewood-webdev /home/dev/backup.sh
#     docker exec -it bythewood-webdev /home/dev/restore.sh
#
# I use volumes for code, claude, ssh, and restic to make rebuilds of the
# container easy without losing project files, claude auth/memory, SSH keys,
# or restic credentials. I have scripts setup on my hosts to rebuild images,
# delete old containers, and start the new containers when I make updates.
#
# NOTE: Fresh volumes will inherit correct dev:dev ownership from the image.
# Existing volumes retain their permissions. If you hit root:root ownership
# issues on existing volumes, fix with:
#     docker exec -it bythewood-webdev sudo chown -R dev:dev /home/dev/.claude /home/dev/code /home/dev/.restic
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
        curl git rsync neovim openssh-client tmux whois nmap unzip htop tree sudo \
        # Backups
        restic \
        # Build tools
        build-essential tzdata ca-certificates \
        # Python
        python3 python3-pip python3-venv \
        # WeasyPrint (PDF rendering for blog.bythewood.me)
        libpango-1.0-0 libpangoft2-1.0-0 libharfbuzz0b libharfbuzz-subset0 \
        # Docker
        docker.io docker-compose-v2 && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    curl -fsSL https://bun.sh/install | env BUN_INSTALL=/usr/local bash

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN npx --yes playwright@latest install --with-deps chromium && \
    chmod -R a+rx /opt/playwright-browsers

RUN ln -snf /usr/share/zoneinfo/UTC /etc/localtime && echo "UTC" > /etc/timezone

RUN useradd -m -G sudo,docker -s /bin/bash dev && \
    echo "dev ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/dev

COPY dotfiles/bash_aliases /home/dev/.bash_aliases
COPY dotfiles/gitconfig /home/dev/.gitconfig
COPY dotfiles/neovim/init.lua /home/dev/.config/nvim/init.lua
COPY dotfiles/tmux.conf /home/dev/.tmux.conf
RUN chown -R dev:dev /home/dev/.bash_aliases /home/dev/.gitconfig /home/dev/.config /home/dev/.tmux.conf && \
    echo "source ~/.bash_aliases" >> /home/dev/.bashrc

# Two symlinks here so claude code works cleanly with our volume layout:
#   .claude.json  -> kept inside the bythewood-claude volume so auth/state
#                    survives container rebuilds (claude writes it to ~ by
#                    default, but ~ isn't a volume — .claude/ is).
#   CLAUDE.md     -> the canonical workspace guide lives in the code repo at
#                    ~/code/CLAUDE.md. Symlinking it into ~ means claude picks
#                    it up when launched from the home dir, not just from
#                    inside ~/code/. Target resolves once the bythewood-code
#                    volume mounts at runtime.
RUN mkdir -p /home/dev/code /home/dev/.claude /home/dev/.ssh /home/dev/.restic && \
    chmod 700 /home/dev/.restic && \
    ln -s /home/dev/.claude/.claude.json /home/dev/.claude.json && \
    ln -s code/CLAUDE.md /home/dev/CLAUDE.md && \
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
    chown -R dev:dev /home/dev/code /home/dev/.claude /home/dev/.ssh /home/dev/.restic

COPY containers/webdev/backup.sh /home/dev/backup.sh
COPY containers/webdev/restore.sh /home/dev/restore.sh
RUN chmod +x /home/dev/backup.sh /home/dev/restore.sh && \
    chown dev:dev /home/dev/backup.sh /home/dev/restore.sh

WORKDIR /home/dev
USER dev

RUN curl -fsSL https://claude.ai/install.sh | bash

CMD ["sleep", "infinity"]

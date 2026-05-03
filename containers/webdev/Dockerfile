# webdev
#
# Ubuntu 24.04 dev container with tmux, neovim, claude code, Bun, uv, Docker
# CLI, and Playwright Chromium. Used as a portable development environment
# across desktop and laptop, with restic backups to Backblaze B2.
#
# Setup is automated by bootstrap.ps1 (idempotent, run from PowerShell on the
# host). It creates volumes, clones taproot into bythewood-code via a helper
# container, builds this image, runs the container, copies the host SSH key
# in, and prompts for restic creds. Taproot itself does not need to be on
# the host; everything operates against the bythewood-code volume.
#
#     irm https://raw.githubusercontent.com/overshard/taproot/master/containers/webdev/bootstrap.ps1 -OutFile bootstrap.ps1
#     powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 laptop      # or "desktop"
#     powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 laptop -Restore   # also pulls B2 snapshot
#
# Connect (TUI):    docker exec -it bythewood-webdev tmux
# Connect (SSH):    ssh -p 2222 dev@localhost
#
# Helper scripts inside the container (in PATH at /home/dev/scripts/):
#     backup     manual restic backup to B2
#     restore    pull latest snapshot from B2
#     sync       git fetch + ff-only pull every repo under ~/code/
#     status     last snapshot per host across both restic repos
#
# The bythewood-* volumes survive image rebuilds, so /home/dev/code,
# /home/dev/.claude, /home/dev/.ssh, and /home/dev/.restic persist. Fresh
# volumes inherit dev:dev ownership from the image. If existing volumes ever
# hit root:root issues:
#     docker exec -it bythewood-webdev sudo chown -R dev:dev \
#         /home/dev/.claude /home/dev/code /home/dev/.restic
#
# Manual build (bootstrap.ps1 does this for you):
#     docker build --tag overshard/webdev:latest -f containers/webdev/Dockerfile .
#
# The docker CLI is installed and /var/run/docker.sock is mounted in so I can
# poke at the host's daemon from inside the container when I need to.


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
        curl git rsync neovim openssh-client openssh-server tmux whois nmap unzip htop tree sudo \
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

COPY containers/webdev/backup.sh /home/dev/scripts/backup
COPY containers/webdev/restore.sh /home/dev/scripts/restore
COPY containers/webdev/sync.sh /home/dev/scripts/sync
COPY containers/webdev/status.sh /home/dev/scripts/status
RUN chmod +x /home/dev/scripts/* && \
    chown -R dev:dev /home/dev/scripts

# sshd setup. Host keys are NOT generated here — the entrypoint creates them
# in the .ssh volume on first start so fingerprints survive image rebuilds.
# pam_loginuid is downgraded to optional because containers don't have
# CAP_AUDIT_WRITE by default and the default `required` makes logins fail.
RUN mkdir -p /run/sshd && \
    sed -i 's/session\s*required\s*pam_loginuid\.so/session optional pam_loginuid.so/g' /etc/pam.d/sshd && \
    printf '%s\n' \
        'PermitRootLogin no' \
        'PasswordAuthentication no' \
        'PubkeyAuthentication yes' \
        'AllowUsers dev' \
        'HostKey /home/dev/.ssh/host_keys/ssh_host_ed25519_key' \
        > /etc/ssh/sshd_config.d/webdev.conf

COPY containers/webdev/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /home/dev
USER dev

RUN curl -fsSL https://claude.ai/install.sh | bash

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]

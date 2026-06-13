# webdev
#
# Ubuntu 24.04 dev container with tmux, neovim, claude code, Bun, uv, cargo,
# Docker CLI, and Playwright Chromium. Used as a portable development environment
# across desktop and laptop, with restic backups to Backblaze B2.
#
# Setup is automated by bootstrap.ps1 (idempotent, run from PowerShell on the
# host). It creates volumes, clones taproot into bythewood-code via a helper
# container, builds this image, runs the container, copies the host git SSH
# key in, and prompts for restic creds. Taproot itself does not need to be on
# the host; everything operates against the bythewood-code volume.
#
#     irm https://raw.githubusercontent.com/overshard/taproot/master/containers/webdev/bootstrap.ps1 -OutFile bootstrap.ps1
#     powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 laptop      # or "desktop"
#     powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 laptop -Restore   # also pulls B2 snapshot
#
# Connect:    docker exec -it bythewood-webdev tmux
#
# Helper scripts inside the container (in PATH at /home/dev/scripts/):
#     restic-backup        manual restic backup to B2
#     restic-restore       pull latest snapshot from B2
#     restic-status        last snapshot per host across both restic repos
#     code-sync            ff-only pull every ~/code/ repo, then clone any
#                          new non-archived owned repos from GitHub
#     server-health-check  ssh into alpine and run the server-side health
#                          script (apk, restic, free, df, docker stats)
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
    PATH="/home/dev/.local/bin:/home/dev/.cargo/bin:$PATH"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # Dev tools
        curl git rsync neovim openssh-client tmux whois nmap unzip htop tree sudo jq \
        # Backups
        restic \
        # Build tools
        build-essential tzdata ca-certificates \
        # Python
        python3 python3-pip python3-venv \
        # Docker (buildx enables BuildKit cache mounts in Dockerfiles)
        docker.io docker-compose-v2 docker-buildx \
        # Node (only used for `npx playwright install` below; bun is the JS runtime)
        nodejs npm && \
    curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    curl -fsSL https://bun.sh/install | env BUN_INSTALL=/usr/local bash

# Playwright Chromium for the Claude playwright MCP. The MCP looks for stable
# Chrome at /opt/google/chrome/chrome, so symlink the playwright build there.
# The chromium-* glob absorbs future playwright revision bumps.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN npx --yes playwright@latest install --with-deps chromium && \
    chmod -R a+rx /opt/playwright-browsers && \
    mkdir -p /opt/google/chrome && \
    ln -snf /opt/playwright-browsers/chromium-*/chrome-linux64/chrome /opt/google/chrome/chrome && \
    test -x /opt/google/chrome/chrome

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

COPY containers/webdev/scripts/ /home/dev/scripts/
RUN for f in /home/dev/scripts/*.sh; do mv "$f" "${f%.sh}"; done && \
    chmod +x /home/dev/scripts/* && \
    chown -R dev:dev /home/dev/scripts

WORKDIR /home/dev
USER dev

# Rust toolchain via rustup (cargo for blog.bythewood.me, darkfurrow.com,
# analytics axum binaries; rust-analyzer for the Claude Code LSP plugin).
# --profile minimal skips offline rust-docs; components add the LSP, linter,
# and formatter.
RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain stable \
        --component rust-analyzer,clippy,rustfmt

RUN curl -fsSL https://claude.ai/install.sh | bash

CMD ["sleep", "infinity"]

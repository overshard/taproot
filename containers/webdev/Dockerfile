# webdev
#
# Ubuntu 24.04 dev container with tmux, neovim, claude code, Bun, uv, cargo, Go,
# Docker CLI, and Playwright Chromium. No nodejs or npm: Bun 1.4 runs Playwright,
# which was the last thing that needed them. Used as a portable development environment
# across desktop and laptop, with restic backups to Backblaze B2.
#
# Setup is automated by bootstrap.ps1 (idempotent, run from PowerShell on the
# host). It creates volumes, clones taproot into bythewood-code via a helper
# container, builds this image, runs the container, copies the host git SSH
# key in, and prompts for restic creds. Taproot itself does not need to be on
# the host; everything operates against the bythewood-code volume.
#
#     irm https://raw.githubusercontent.com/overshard/taproot/main/containers/webdev/bootstrap.ps1 -OutFile bootstrap.ps1
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

# BUN_INSTALL is set here, persistently, rather than only for the installer
# below: it is also what decides where `bun install -g` puts a global binary.
# Without it globals land in ~/.bun/bin rather than /usr/local/bin, which is
# where npm used to put them and where the rest of this image looks.
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    BUN_INSTALL=/usr/local \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    PATH="/home/dev/.local/bin:/home/dev/.cargo/bin:/usr/local/go/bin:/home/dev/go/bin:$PATH"

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
        docker.io docker-compose-v2 docker-buildx && \
    curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    curl -fsSL https://bun.sh/install | env BUN_INSTALL=/usr/local bash

# There is no nodejs or npm in this image. Bun 1.4 (2026-08-20) runs Playwright,
# which was the only thing still keeping them here, so both came out.
#
# This symlink is load bearing rather than cosmetic. npm-published CLIs ship a
# `#!/usr/bin/env node` shebang, so @playwright/cli installs fine under bun and
# then dies instantly with "env: 'node': No such file or directory" without it.
# Bun is argv-compatible enough to stand in, which is the same trick the status
# site already uses through `bun run --bun`, promoted to a global symlink.
#
# `npm` is deliberately NOT symlinked. `npm install` and `npm run` would map
# onto bun cleanly, but `npm ci` has no bun equivalent and would fail in a
# confusing way. Nothing in this workspace calls npm any more, and a clear
# "command not found" beats a subtly wrong one.
# Verified by running a script the way a shebang does, not by `node --version`:
# bun invoked as `node` with only a flag has no script to execute and exits 1,
# so anything that probes the Node version will still fail. Nothing here does,
# but that is the sharp edge of this symlink and it is worth knowing about.
RUN ln -sf /usr/local/bin/bun /usr/local/bin/node && \
    echo 'console.log("node shim ok")' > /tmp/shim.js && \
    node /tmp/shim.js && rm /tmp/shim.js

# Playwright Chromium for the `playwright` skill, which drives the browser via
# @playwright/cli (installed below) rather than an MCP. Some tools look for stable
# Chrome at /opt/google/chrome/chrome, so symlink the playwright build there.
# The chromium-* glob absorbs future playwright revision bumps.
# @playwright/cli: token-efficient command-line browser automation. The
# `playwright` skill (~/.claude/skills/playwright) uses this instead of the
# Playwright MCP; it writes page state to disk so only what's needed enters
# context (~4x fewer tokens than the MCP on a typical task).
#
# PINNED, and the pin is load bearing rather than tidiness.
#
# This was unpinned, alongside a separate `playwright@latest` for the browsers:
# two installs that could drift apart from each other between any two builds.
# They did, and the newer one does not work here. Measured, holding everything
# else constant and running in a fresh container each time:
#
#     @playwright/cli 0.1.14 -> playwright-core 1.61 -> Chromium 1226   works
#     @playwright/cli 0.1.18 -> playwright-core 1.63 -> Chromium 1237   fails
#     unpinned (at time of writing)             -> Chromium 1234        fails
#
# The failure is "No usable sandbox" from the zygote host. Chrome-for-Testing
# builds ship no setuid chrome-sandbox and rely entirely on unprivileged user
# namespaces, and something in this Docker Desktop on WSL2 setup denies them to
# the newer builds. Ruled out by testing rather than assumed: it is not the
# browser directory's permissions (a+rwx fails identically), not seccomp
# (`--security-opt seccomp=unconfined` does not help), and not capabilities
# (`--cap-add SYS_ADMIN` does not help). Nothing about it was caused by
# dropping nodejs; a rebuild on the old image would have hit it too.
#
# If a newer Chromium is wanted before that is understood, the escape hatch is
# to launch with `chromiumSandbox: false` / `--no-sandbox`, which is a real
# security tradeoff and so is not done here by default.
#
# Bump deliberately, and re-run the playwright skill against a real page after.
ARG PLAYWRIGHT_CLI_VERSION=0.1.14
RUN bun install -g @playwright/cli@${PLAYWRIGHT_CLI_VERSION} && \
    command -v playwright-cli && playwright-cli --help >/dev/null

# The browsers come from the CLI's own bundled playwright-core rather than a
# separately resolved `playwright@latest`, so the download and the code that
# drives it can never disagree about which Chromium revision to use. That skew
# is exactly what an unpinned pair of installs invites.
#
# Some tools look for stable Chrome at /opt/google/chrome/chrome, so the
# playwright build is symlinked there. The chromium-* glob absorbs revision
# bumps when the pin above moves.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN CORE="$(find /usr/local/install/global -path '*/playwright-core/cli.js' | head -1)" && \
    test -n "$CORE" && \
    node "$CORE" install --with-deps chromium && \
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

# Go toolchain, installed from upstream tarball rather than apt because
# Ubuntu 24.04 ships a version several releases behind. This is what the
# workspace is moving to: see memory decisions/0008. The checksum is pinned so
# a tampered or truncated download fails loudly instead of producing a
# half-working toolchain.
ARG GO_VERSION=1.27.0
ARG GO_SHA256=675c26c449cbb18fc24b74650de1eabbae6e16f64326fd85a283fb3b58280685
RUN curl -fsSLO "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" && \
    echo "${GO_SHA256}  go${GO_VERSION}.linux-amd64.tar.gz" | sha256sum -c - && \
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz" && \
    rm "go${GO_VERSION}.linux-amd64.tar.gz"

WORKDIR /home/dev
USER dev

# Rust toolchain via rustup (cargo for the axum apps: blog.bythewood.me plus the
# archived analytics-rust, status-rust, finance-rust, repos-rust and
# darkfurrow.com). --profile minimal skips offline
# rust-docs; components add the linter and formatter. No rust-analyzer: Rust work
# goes through the `rust` skill, not an LSP plugin (the rust-analyzer-lsp plugin
# was removed), and neovim here isn't configured for LSP.
RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain stable \
        --component clippy,rustfmt

RUN curl -fsSL https://claude.ai/install.sh | bash

CMD ["sleep", "infinity"]

# webdev
#
# Debian 13. Go, Python (uv), Bun, Claude Code, Docker CLI, typst, Playwright.
# No nodejs, no npm, no Rust. Work lives in the four bythewood-* volumes, so the
# container itself is disposable.
#
# Everything below is driven by the Makefile at the root of this repo, which is
# also the build context. From a clone:
#
#     make up          create whatever is missing and start it; safe to re-run
#     make update      rebuild this image and replace the running container
#     make doctor      what exists, what is running, and what to type next
#     make shell       get in, via tmux
#
# `make update` works from inside this container. Replacing it directly cannot:
# `docker rm --force` on your own container kills the make process doing the
# removing, so a throwaway docker:cli is what performs the swap. Your shell
# drops when the old container goes; `docker exec -it bythewood-webdev tmux`
# from the host brings you back.
#
# A machine that has never run this needs Docker, and a git key at
# ~/.ssh/home_key that is on GitHub:
#
#     make up
#     docker cp $HOME/.ssh/home_key bythewood-webdev:/home/dev/.ssh/home_key
#     docker exec bythewood-webdev sh -c "chmod 700 /home/dev/.ssh && chmod 600 /home/dev/.ssh/home_key"
#     docker exec -it bythewood-webdev restic-setup
#     docker exec -it bythewood-webdev restic-restore
#
# The 600 matters: ssh refuses anything looser, and a key copied off Windows
# arrives with no usable mode. `restic-setup` prompts for the B2 credentials and
# checks them, so there is no file to hand-edit and get subtly wrong; then
# `restic-restore` is the only way the memory vault comes back, that repo having
# no git remote anywhere. `make doctor` reports on all of this.
#
# Gotchas: --init or tmux leaves zombies. docker.sock is root:root 660, so
# docker needs sudo in here. --publish is what makes port 8000 reachable from
# the host browser. Bind mounts under /home/dev silently mount empty, because
# the daemon is Docker Desktop and resolves paths on the Windows side; use
# named volumes.

FROM debian:trixie-slim

# BUN_INSTALL is persistent: it also decides where `bun install -g` puts globals.
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    BUN_INSTALL=/usr/local \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    PATH="/home/dev/.local/bin:/home/dev/scripts:/usr/local/go/bin:/home/dev/go/bin:$PATH"

# Docker's repo, not Debian's: trixie has no docker-compose-v2 package. Client
# only, never the daemon. The second update is required by adding that repo and
# refreshes conditionally; the lists stay until the playwright step below, which
# runs apt itself, so nothing is downloaded twice.
# jq is required by code-sync. No pip, no python3-venv, uv covers both.
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" \
        > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        git rsync neovim openssh-client tmux \
        unzip xz-utils htop tree sudo jq restic sqlite3 poppler-utils \
        build-essential tzdata python3 \
        docker-ce-cli docker-compose-plugin docker-buildx-plugin

RUN curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    curl -fsSL https://bun.sh/install | bash

# Load bearing: npm-published CLIs have a `#!/usr/bin/env node` shebang and die
# without this. `node --version` does not work under it, so the check runs a real
# script. npm is not symlinked; `npm ci` has no bun equivalent.
RUN ln -sf /usr/local/bin/bun /usr/local/bin/node && \
    echo 'console.log("node shim ok")' > /tmp/shim.js && \
    node /tmp/shim.js && rm /tmp/shim.js

# Upstream tarball, not apt, which lags releases.
ARG GO_VERSION=1.27.0
ARG GO_SHA256=675c26c449cbb18fc24b74650de1eabbae6e16f64326fd85a283fb3b58280685
RUN curl -fsSLO "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" && \
    echo "${GO_SHA256}  go${GO_VERSION}.linux-amd64.tar.gz" | sha256sum -c - && \
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz" && \
    rm "go${GO_VERSION}.linux-amd64.tar.gz" && \
    go version

# Pinned to the same version orchard's sites pin. musl is the only linux x86_64
# build typst ships; it is static and runs fine on glibc.
ARG TYPST_VERSION=0.14.0
ARG TYPST_SHA256=99816d2982de08d2b091bac56b59b2faa523a10e1378ad3cdd68e35b8eb74b3d
RUN curl -fsSL -o /tmp/typst.tar.xz \
      "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-x86_64-unknown-linux-musl.tar.xz" && \
    echo "${TYPST_SHA256}  /tmp/typst.tar.xz" | sha256sum -c - && \
    tar -xJf /tmp/typst.tar.xz -C /tmp && \
    mv /tmp/typst-x86_64-unknown-linux-musl/typst /usr/local/bin/typst && \
    rm -rf /tmp/typst.tar.xz /tmp/typst-x86_64-unknown-linux-musl && \
    typst --version

# Pin is load bearing: 0.1.14 gives Chromium 1226 and drives a page, while 0.1.18
# (1237) and unpinned (1234) both die with "No usable sandbox" under Docker
# Desktop on WSL2. Bump deliberately and drive a real page after. Browsers come
# from the CLI's own playwright-core so the two cannot disagree on a revision.
# Some tools want Chrome at the /opt path. This step runs apt, hence the cleanup.
ARG PLAYWRIGHT_CLI_VERSION=0.1.14
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN bun install -g @playwright/cli@${PLAYWRIGHT_CLI_VERSION} && \
    playwright-cli --help >/dev/null && \
    CORE="$(find /usr/local/install/global -path '*/playwright-core/cli.js' | head -1)" && \
    test -n "$CORE" && \
    node "$CORE" install --with-deps chromium && \
    chmod -R a+rx /opt/playwright-browsers && \
    mkdir -p /opt/google/chrome && \
    ln -snf /opt/playwright-browsers/chromium-*/chrome-linux64/chrome /opt/google/chrome/chrome && \
    test -x /opt/google/chrome/chrome && \
    rm -rf /var/lib/apt/lists/*

RUN ln -snf /usr/share/zoneinfo/UTC /etc/localtime && echo "UTC" > /etc/timezone

# Debian's /etc/profile assigns PATH outright, so a login shell (what tmux panes
# get) drops everything the ENV added. The ENV still covers plain `docker exec`.
RUN printf '%s\n' \
    'export PATH="/home/dev/.local/bin:/home/dev/scripts:/usr/local/go/bin:/home/dev/go/bin:$PATH"' \
    > /etc/profile.d/10-dev-path.sh && chmod 644 /etc/profile.d/10-dev-path.sh

# Everything in the bythewood-* volumes is owned by 1001. Debian has no default
# 1000 user, so an unpinned useradd takes 1000 and every volume mounts owned by a
# stranger. Do not remove the -u.
RUN useradd -m -u 1001 -G sudo -s /bin/bash dev && \
    echo "dev ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/dev

COPY dotfiles/bash_aliases /home/dev/.bash_aliases
COPY dotfiles/gitconfig /home/dev/.gitconfig
COPY dotfiles/neovim/init.lua /home/dev/.config/nvim/init.lua
COPY dotfiles/tmux.conf /home/dev/.tmux.conf
COPY containers/webdev/scripts/ /home/dev/scripts/

# .claude.json lives in the volume so auth survives a rebuild. CLAUDE.md resolves
# once bythewood-code mounts.
RUN mkdir -p /home/dev/code /home/dev/.claude /home/dev/.ssh /home/dev/.restic && \
    for f in /home/dev/scripts/*.sh; do mv "$f" "${f%.sh}"; done && \
    chmod +x /home/dev/scripts/* && \
    echo "source ~/.bash_aliases" >> /home/dev/.bashrc && \
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
    chmod 700 /home/dev/.ssh /home/dev/.restic && \
    chmod 600 /home/dev/.ssh/config && \
    chown -R dev:dev /home/dev

WORKDIR /home/dev
USER dev

RUN curl -fsSL https://claude.ai/install.sh | bash

CMD ["sleep", "infinity"]

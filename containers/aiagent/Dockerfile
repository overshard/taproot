# aiagent
#
# Qwen3.5-9B at 128k context on a llama.cpp CUDA server, plus the pi coding
# agent pointed at it. Sized for an 8GB Ampere card. No telemetry, no update
# checks, no published port. Deliberately has no Go, bun or node: this runs an
# agent, it does not build.
#
# Commands are one line each so they paste into PowerShell and sh alike. Run
# them from a clone of this repo; the build needs it as context.
#
# Build or rebuild (~15 min the first time):
#     docker build --tag overshard/aiagent:latest -f containers/aiagent/Dockerfile .
#
# Fetch the weights once, the only step that reaches Hugging Face:
#     make models
#
# Replace a running container with the new image:
#     docker rm --force bythewood-aiagent
#     docker run --detach --name bythewood-aiagent --init --gpus all --volume bythewood-code:/home/ai/code --volume bythewood-ssh:/home/ai/.ssh --volume bythewood-ai-models:/models overshard/aiagent:latest
#
# Get in, then type: pi
#     docker exec -it bythewood-aiagent tmux
#
# Stop, which frees the VRAM:
#     docker stop bythewood-aiagent
#
# Serve a different model without rebuilding, by appending llama-server flags:
#     docker run ... overshard/aiagent:latest -hf <repo>:<quant> --alias local
#
# Gotchas: --gpus all or it loads nothing. --init or tmux leaves zombies. The
# server binds loopback and publishes nothing, so only pi in here reaches it and
# it needs no API key; that is also why the weights volume is the only state.
# Weights plus a 128k q4_0 KV cache sit at about 96% of an 8GB card, so a second
# CUDA process will not fit alongside it.


FROM debian:trixie-slim AS build

# CUDA 13.2 produces gibberish from low-bit quants.
ARG CUDA=13-3

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git cmake ninja-build build-essential \
        libcurl4-openssl-dev && \
    curl -fsSLo /tmp/keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i /tmp/keyring.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        cuda-nvcc-${CUDA} cuda-cudart-dev-${CUDA} libcublas-dev-${CUDA} && \
    rm -rf /var/lib/apt/lists/* /tmp/keyring.deb

ENV PATH=/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# sm_86 alone keeps the build short; change it for another card.
# FA_ALL_QUANTS is what makes flash attention work with a quantized KV cache.
# Static libs because upstream ships shared objects without a SONAME, which
# ldconfig then refuses to cache.
RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp /tmp/src && \
    cmake -S /tmp/src -B /tmp/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DGGML_CUDA=ON \
        -DCMAKE_CUDA_ARCHITECTURES=86 \
        -DGGML_CUDA_FA_ALL_QUANTS=ON \
        -DGGML_NATIVE=OFF \
        -DLLAMA_CURL=ON \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF && \
    cmake --build /tmp/build --target llama-server llama-bench -j"$(nproc)" && \
    strip /tmp/build/bin/llama-server /tmp/build/bin/llama-bench


FROM debian:trixie-slim

ARG CUDA=13-3

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    HOME=/home/ai \
    LLAMA_CACHE=/models \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Node, not bun: pi's extension installer shells out to `npm root -g`.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git openssh-client jq tmux less nano procps \
        ripgrep fd-find iptables libgomp1 libcurl4 && \
    curl -fsSLo /tmp/keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i /tmp/keyring.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        cuda-cudart-${CUDA} libcublas-${CUDA} && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g @earendil-works/pi-coding-agent && \
    npm cache clean --force && \
    rm -rf /var/lib/apt/lists/* /tmp/keyring.deb

COPY --from=build /tmp/build/bin/llama-server /tmp/build/bin/llama-bench /usr/local/bin/

# Debian's /etc/profile assigns PATH outright, so a login shell (every tmux
# pane) drops anything ENV added. Both this and the ENV above are needed.
RUN printf 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' \
        > /etc/profile.d/10-path.sh

# UID 1001 matches webdev's dev user so both share the bythewood-code volume.
# pi fetches its own rg and fd into .pi/agent/bin on first run, which offline
# mode blocks, so link the packaged ones where it looks for them.
RUN useradd -m -u 1001 -s /bin/bash ai && \
    mkdir -p /home/ai/code /home/ai/.pi/agent/bin /models && \
    ln -s /usr/bin/rg /home/ai/.pi/agent/bin/rg && \
    ln -s /usr/bin/fdfind /home/ai/.pi/agent/bin/fd && \
    chown -R ai:ai /home/ai /models

COPY dotfiles/bash_aliases /home/ai/.bash_aliases
COPY dotfiles/tmux.conf /home/ai/.tmux.conf
# pi walks up from its cwd to find this.
COPY --chown=ai:ai <<'AGENTS' /home/ai/AGENTS.md
# AGENTS.md

## Tools

You have `read`, `bash`, `edit`, `write`, and web tools: `web_search`,
`fetch_content` and `get_search_content`. Use them. Do not answer from memory
when a fact can be looked up.

## Before adding any dependency

Look up the current stable version before writing it into a manifest. Training
data is out of date and will suggest an old major version.

1. `web_search` for the package's latest stable release.
2. Write the version you found, not one you remember.
3. Say in your summary which version you found.

## Go

- Final images are minimal and have no C compiler. Any SQLite driver must be
  pure Go and must build with `CGO_ENABLED=0`. `modernc.org/sqlite` works;
  `mattn/go-sqlite3` needs cgo and fails at runtime.
- `embed` patterns cannot reach outside the package directory and do not
  support `**`.

## Frontend

Bun and Vite, no npm and no nodejs. Build the frontend before claiming it
works: `bun install && bun run build`. Vite emits a manifest so the server can
resolve content hashed filenames.

## Definition of done

`go build ./...` and `go vet ./...` both exit zero, and the frontend builds.
Run them. Do not report success without running them. A program that compiles
but serves a blank page is not done.
AGENTS
# extended-keys lets pi see modified Enter. Appended rather than added to the
# shared dotfile so webdev's tmux is untouched.
RUN chown ai:ai /home/ai/.bash_aliases /home/ai/.tmux.conf && \
    echo "source ~/.bash_aliases" >> /home/ai/.bashrc && \
    printf 'set -g extended-keys on\nset -g extended-keys-format csi-u\n' >> /home/ai/.tmux.conf

WORKDIR /home/ai/code
USER ai

# web-search.json pins duckduckgo because the default chain ends at Exa's
# public endpoint when no API keys are set, and workflow "none" because the
# default blocks on a browser curator that never opens in a container.
RUN pi install npm:pi-web-access && \
    printf '%s' '{"providers":{"local":{"baseUrl":"http://127.0.0.1:8000/v1","api":"openai-completions","apiKey":"none","compat":{"supportsDeveloperRole":false,"supportsReasoningEffort":false},"models":[{"id":"local","name":"local","contextWindow":131072,"maxTokens":8192,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0}}]}}}' \
        > /home/ai/.pi/agent/models.json && \
    printf '%s' '{"packages":["npm:pi-web-access"],"enableInstallTelemetry":false,"enableAnalytics":false}' \
        > /home/ai/.pi/agent/settings.json && \
    printf '%s' '{"searchProvider":"duckduckgo","workflow":"none","autoOpenBrowser":false}' \
        > /home/ai/.pi/web-search.json

# Set after the install above so it cannot block the build.
ENV PI_OFFLINE=1 \
    PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0 \
    DO_NOT_TRACK=1 \
    LLAMA_ARG_OFFLINE=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false

#   --no-mmproj   refuse the vision projector, which costs VRAM and makes the
#                 server disable prompt caching
#   --parallel 1  hybrid attention corrupts context checkpoints under
#                 multi-slot load (ggml-org/llama.cpp#20222), and one slot
#                 keeps the prompt cache an agent loop depends on
#   --flash-attn  required for a quantized KV cache; K and V must match type
ENTRYPOINT ["/usr/local/bin/llama-server"]
CMD ["-hf", "unsloth/Qwen3.5-9B-GGUF:Q4_K_S", \
     "--alias", "local", \
     "--host", "127.0.0.1", "--port", "8000", \
     "--ctx-size", "131072", \
     "--n-gpu-layers", "999", \
     "--flash-attn", "on", \
     "--cache-type-k", "q4_0", "--cache-type-v", "q4_0", \
     "--parallel", "1", \
     "--batch-size", "2048", "--ubatch-size", "256", \
     "--no-mmproj", \
     "--jinja", \
     "--reasoning", "off", \
     "--temp", "0.7", "--top-p", "0.8", "--top-k", "20"]

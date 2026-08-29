# aiagent
#
# Local AI in one container: a llama.cpp CUDA server holding a 9B coding model
# at 128k context, plus the pi coding agent. Sized for an 8GB Ampere card.
# No telemetry, no update checks, no published port.
#
# Build (from the repo root, ~15 min the first time):
#     docker build --tag overshard/aiagent:latest -f containers/aiagent/Dockerfile .
#
# Fetch the weights once, the only time it needs Hugging Face:
#     docker run --rm --env LLAMA_ARG_OFFLINE=false --volume bythewood-ai-models:/models overshard/aiagent:latest --list-devices
#
# Run:
#     docker run --detach --name bythewood-aiagent --init --gpus all --volume bythewood-code:/home/ai/code --volume bythewood-ssh:/home/ai/.ssh --volume bythewood-ai-models:/models overshard/aiagent:latest
#
# Connect:  docker exec -it bythewood-aiagent tmux      then type: pi
# Stop:     docker stop bythewood-aiagent               (frees the VRAM)
#
# Serve a different model without rebuilding, by appending llama-server flags:
#     docker run ... overshard/aiagent:latest -hf <repo>:<quant> --alias local ...


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

# Binds loopback and publishes nothing, so only pi in this container can reach
# it and it needs no API key.
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

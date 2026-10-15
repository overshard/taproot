# The aiagent container

Qwen3.5-9B at 128k context on a llama.cpp CUDA server, plus the
[pi](https://pi.dev) coding agent pointed at it. Sized for an 8GB Ampere card.
The server binds loopback and publishes nothing, so only pi inside the container
can reach it and it needs no API key.

```sh
make models             # once, the only step that reaches Hugging Face
make up C=aiagent
make shell C=aiagent    # then type: pi
make stop C=aiagent     # frees the VRAM
```

Serving a different model needs no rebuild, just a one-off run against the same
weights volume:

```sh
make serve MODEL=<hf-repo>:<quant>
```

In `aiagent`, `webdev-exec` runs a command over in `webdev` against the same
source tree. `go`, `gofmt` and `bun` are symlinks to it, so those just work.

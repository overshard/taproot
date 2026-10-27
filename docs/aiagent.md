# The aiagent container

Ornith 1.5 9B at Q4_K_M plus the [pi](https://pi.dev) coding agent, sized for
an 8GB Ampere card. On the desktop pi uses the model gateway at
`llm.bythewood.me` with a 64k window and nothing loads in here, since one card
can't hold the gateway's copy and a second one. With no key stored, or the
gateway not answering, it serves the same model itself at 128k context on a
llama.cpp CUDA server instead. That server binds loopback and publishes nothing,
so only pi inside the container can reach it and it needs no API key.

```sh
make llm-key            # once, the key from: cd ~/code/orchard && make llm-key NAME=aiagent
make models             # only without a gateway, the one step that reaches Hugging Face
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

# pi in webdev

webdev carries the [pi](https://pi.dev) coding agent and Ornith 1.5 9B at
Q4_K_M on a llama.cpp CUDA server, sized for an 8GB Ampere card. Nothing goes
to the llm gateway in orchard, the model runs right here.

```sh
make models     # once, about 5.4GB from Hugging Face into bythewood-models
make update     # webdev needs replacing once to pick up the card and the volume
pi              # from anywhere in webdev
```

`~/scripts/pi` is a small wrapper in front of the real `/usr/local/bin/pi`. The
first pi starts `llama-server` on `127.0.0.1:8080` with a 64k window and the
last one to exit stops it, so the card is only held while a pi is open. In
between the server drops the model after three idle minutes and loads it again
on the next turn. `pi install`, `pi list` and the other subcommands skip all of
that. The server's log is `~/.cache/ornith.log`.

pi installs its packages with bun, through `npmCommand` in
`~/.pi/agent/settings.json`, so there's no node or npm. Its rules live in
`containers/webdev/AGENTS.md`, which lands at `~/AGENTS.md`.

## Things that will bite you

- The card holds one copy of Ornith, and orchard's llm gateway loads its own
  for chat and dash. pi refuses to start with less than 6500MiB free and says
  why. The gateway lets go 3 minutes after its last call, and dash's briefs
  wait for a busy card on their own, but a chat turn while pi has the model
  will fail.
- A Windows driver update leaves webdev pointing at the old driver, and pi says
  there's no GPU. `make update` fixes it.
- webdev only gets `--gpus all` where docker has the nvidia runtime, so on a
  machine without a card pi won't start and everything else works.
- pi runs as `dev`, with the docker socket and passwordless sudo, so AGENTS.md
  is the only thing keeping it off them.

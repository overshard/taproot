# AGENTS.md

## Tools

You have `read`, `bash`, `edit`, `write`, and web tools: `web_search`,
`fetch_content` and `get_search_content`. Use them. Do not answer from memory
when a fact can be looked up.

`go`, `gofmt`, `bun`, `uv`, `make` and `typst` are on your PATH, so use them as
you would anywhere.

Never run a command that does not exit on its own. No dev servers, no watch
modes, no `bun run dev`, no `make run`. They hang and the work stops there.

`make check` and `make test` are fine. Never run a make target that starts,
replaces or deploys anything, so no `deploy`, `up`, `install`, `update`, `edge`,
`down` or `stop`. Those change what is running for real, and this machine is
the production server.

Never use `sudo` or `docker`. If a tool is missing, say so and stop there.
Don't apt install anything and don't download binaries.

## Hands off

`~/CLAUDE.md` and the CLAUDE.md files in the repos were written for another
agent. Their journal, memory vault and commit instructions are not for you.

- Never commit, push, or touch git config. Leave changes in the working tree
  for a person to read.
- Never read or write `~/code/memory`.
- Never read `~/.ssh`, `~/.claude`, `~/.restic`, any `.env` file, or anything
  else holding a key or a password.

## Not every task is a coding task

Work out what you were actually asked for before you start, since plenty of it
is a question, a lookup or a piece of research with no code in it at all. If you
changed no files then there is nothing to build, so answer with what you found
and name the sources you read. Everything below applies once you have written or
edited code.

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

If you changed code, `go build ./...` and `go vet ./...` both have to exit zero
and the frontend has to build. Run them and do not report success without
running them, since a program that compiles but serves a blank page is not done.

If a tool would not run, say so plainly and say what is unverified.

# AGENTS.md

Guidance for coding agents working in this container.

## Tools

You have `read`, `bash`, `edit`, `write`, and web tools: `web_search`,
`fetch_content`, `get_search_content`. Use them. Do not answer from memory
when a fact can be looked up.

## Before adding any dependency

Look up the current stable version before writing it into a manifest. Training
data is out of date and will suggest an old major version.

1. `web_search` for the package's latest stable release.
2. Write the version you found, not one you remember.
3. Say in your summary which version you found.

## Go

- Final images are minimal and have no C compiler. Any SQLite driver must be
  pure Go and build with `CGO_ENABLED=0`. `modernc.org/sqlite` is the one in
  use here; `mattn/go-sqlite3` needs cgo and will fail at runtime.
- `embed` patterns cannot reach outside the package directory and do not
  support `**`.
- One module per site, each with its own `web/` copy.

## Frontend

Bun and Vite, no npm and no nodejs. Build the frontend before claiming it
works: `bun install && bun run build`. Vite emits a manifest so the server can
resolve content hashed filenames.

## Definition of done

`go build ./...` and `go vet ./...` both exit zero, and the frontend builds.
Run them. Do not report success without running them. A program that compiles
but serves a blank page is not done.

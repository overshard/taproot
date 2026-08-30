---
name: rust
description: Work on the Rust axum projects in this workspace (blog.bythewood.me, plus the archived analytics-rust, status-rust, finance-rust, repos-rust and darkfurrow.com). Invoke when building, running, editing, or debugging any of these single-binary axum + Vite + SQLite apps. Covers the shared architecture, dev commands, and the gotchas that bite (Jinja URL escaping, embedded Typst PDF, the Vite manifest). Always read the project's own note in code/memory/projects/<name>.md first for project-specific detail.
---

# Rust axum projects

Six apps share one architecture: a single axum binary with a Vite-built frontend and an
embedded SQLite database. Only `blog.bythewood.me` is still active, and `analytics-rust`,
`status-rust`, `finance-rust`, `repos-rust` and `darkfurrow.com` were archived on 2026-08-26
and their local checkouts have no git remotes. **Before editing one, read its living note**
`~/code/memory/projects/<name>.md` (analytics-rust, status-rust, finance-rust, blog,
darkfurrow, repos-rust):
that note is the authoritative per-project guidance (env vars, deploy, quirks) that used
to live in a per-project CLAUDE.md.

This skill is instructions only. There is no LSP here (we dropped the rust-analyzer-lsp
plugin). Rely on `cargo check`/`cargo build` for diagnostics.

## Shared shape

- Tiny `src/main.rs` entry, and `src/app.rs` builds `AppState` + the `Router`. Per-feature
  route modules live under `src/routes/`.
- Helpers: `src/render.rs` (template render), `src/middleware.rs` (request log + 404),
  `src/templates.rs` (minijinja env + filters).
- Frontend in `frontend/` (Vite) builds to `dist/`, served at `/static/` with
  content-hashed filenames. The binary reads `dist/.vite/manifest.json` to resolve the
  hashed names in templates. **If assets 404, the manifest or `dist/` is stale rebuild
  the frontend.**
- minijinja 2 for Jinja2-faithful templates, tower-cookies for signed sessions, sqlx 0.8
  on SQLite (WAL, `synchronous=NORMAL`, busy timeout, foreign keys on) with migrations
  auto-applied on boot.

## Dev commands (all projects)

- `make run` (default): installs frontend deps if needed, then runs Vite watch +
  `cargo run` concurrently on **port 8000**. Visit `http://localhost:8000`.
- `make build`: Vite assets + release binary at `target/release/<name>` plus `dist/`.
- `make start`: run the release binary (after `make build`).
- `make clean`: `cargo clean` plus removing `dist/`, `node_modules/`, the SQLite db.
- `sudo docker build .`: production image. **No tests, no linters** in any project.
- Rust deps via `cargo` (`Cargo.toml`/`Cargo.lock`), JS deps via `bun` from `frontend/`.
- Local builds need `pkg-config` + OpenSSL headers, which the Docker build supplies.

## Gotchas

- **Jinja URL escaping.** All projects ship a Jinja2-faithful HTML formatter in
  `src/templates.rs` so `/` is not escaped to `&#x2f;` in URLs. If URLs render mangled,
  that filter is the place to look do not work around it in templates.
- **PDF reports** are rendered in-process via embedded Typst (`typst` + `typst-pdf` +
  `typst-kit` 0.14), no chromium subprocess. `status` still bundles chromium, but only
  for Lighthouse audits, not PDF. Alpine runtimes must install body/mono/fallback fonts
  (jetbrains-mono, dejavu, liberation, fontconfig) so Typst finds fonts.
- **Ports.** Every container listens on 8000 internally in dev and prod. In prod no host
  ports are published, and Caddy reverse-proxies by container name on 8000.

## Deploy

`git push server master` triggers a post-receive hook: `docker compose up --build
--detach`, then reattaches the container to the shared `bythewood-edge` Docker network.
Manifest: `~/code/taproot/hosts/alpine/srv/projects.conf`.

# Claude Code config

Version-controlled Claude Code config for the webdev machine: skills, the status line,
and shareable global settings. Lives in taproot (a **public** repo), symlinked into the
untracked `~/.claude/` volume so edits here are live immediately and survive container
rebuilds.

## What lives here (and what must not)

taproot is public, so only non-secret config goes here.

| In taproot (public)        | What it is                                              |
|----------------------------|--------------------------------------------------------|
| `skills/`                  | Our own skills (no MCPs, no plugins)                    |
| `status-line.sh`           | The status line script (usg/ctx/cwd/git/ET clock)      |
| `settings.json`            | Reference template of global settings (NOT symlinked)  |

`settings.json` here is a **reference copy**, not a live symlink. The live
`~/.claude/settings.json` carries permission-posture flags
(`skipDangerousModePermissionPrompt`, `defaultMode`), which the Claude Code harness
will not let an agent auto-symlink or auto-edit (it flags self-modification). Keep the
live file machine-local and update this template by hand when the posture changes.

**Never put here** (kept in the `~/.claude` volume + restic only): `.credentials.json`,
`.claude.json`, `settings.local.json` (per-machine permission grants), and anything with
tokens, keys, or session/auth state.

## Skills

Plain skill dirs, each `skills/<name>/SKILL.md` with YAML frontmatter (`name`,
`description`) and a Markdown body. We use skills instead of MCPs/plugins:

- **journal** wrap the session into the `~/code/memory` vault (the memory contract).
- **playwright** browser automation via `playwright-cli` (token-efficient, replaces the
  Playwright MCP).
- **rust** working on the axum + Vite + SQLite projects (replaces rust-analyzer-lsp; note
  this drops live LSP diagnostics, a skill is instructions only).

## Setup on a fresh machine

`~/.claude` is a Docker volume (persistent, restic-backed), so on an existing machine
these symlinks already survive rebuilds. Only a brand-new volume needs this one-time
wiring, after `~/code/taproot` is cloned:

```bash
ln -snf ~/code/taproot/dotfiles/claude/skills         ~/.claude/skills
ln -snf ~/code/taproot/dotfiles/claude/status-line.sh ~/.claude/status-line.sh
# settings.json is machine-local; copy the template instead of symlinking:
cp ~/code/taproot/dotfiles/claude/settings.json ~/.claude/settings.json   # then re-add machine-local bits
```

`settings.json`'s `statusLine.command` points at `~/.claude/status-line.sh`, which the
status-line symlink redirects back here, so no path edit is needed.

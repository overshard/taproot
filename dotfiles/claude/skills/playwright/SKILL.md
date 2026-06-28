---
name: playwright
description: Drive a real browser for screenshots, page inspection, and UI verification using the playwright-cli command line tool (not an MCP). Invoke when asked to open a page, click through a flow, take a screenshot, inspect selectors, verify rendered UI, or generate a Playwright test from a recorded flow. Token-efficient: state is saved to disk and you read only what you need, instead of an MCP streaming whole accessibility trees into context.
---

# Browser automation with playwright-cli

We use Microsoft's `playwright-cli` (the `@playwright/cli` package) instead of the
Playwright MCP server. The MCP streams the full accessibility tree and screenshot bytes
into context on every step (~4x the tokens); the CLI writes that state to disk and lets
you read only the snapshot lines you need. Same browser, far cheaper context.

The webdev container already ships Playwright Chromium at `/opt/playwright-browsers`
(symlinked to `/opt/google/chrome/chrome`), so no extra browser download is needed.

## Setup (one-time, per machine)

```bash
playwright-cli --version || npm install -g @playwright/cli
```

If it is missing and `npm` is unavailable, install via the project's JS toolchain or
add it to the webdev Dockerfile (see `~/code/taproot/containers/webdev/Dockerfile`,
near the existing Playwright Chromium step).

## Core workflow

```bash
playwright-cli open http://localhost:8000/login   # add --headed to watch it visually
playwright-cli snapshot                            # accessibility tree + element refs
playwright-cli click <ref>                         # refs come from the latest snapshot
playwright-cli type "hello"
playwright-cli press Enter
playwright-cli check <ref>
playwright-cli screenshot                          # PNG written to disk
```

After each command the CLI prints the current page URL, title, and a path to the
snapshot file. **Read that snapshot file to get element refs for the next command** do
not guess refs.

## Where output lands

- Snapshots: `.playwright-cli/page-<timestamp>.yml` (the accessibility tree with refs).
- Screenshots: PNG files on disk; open them with the Read tool to view.

Read these files on demand rather than dumping them; that is the entire point of using
the CLI over the MCP.

## Notes for this workspace

- Every app in this workspace serves on **port 8000** in dev (`make run`). Log in at
  `/login` where the app has auth (analytics, status, finance).
- Good uses here: confirm a rendered template change, screenshot a chart/map/PDF page,
  walk a multi-step form, or record a flow to scaffold a test.

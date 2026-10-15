---
name: playwright
description: Drive a real browser for screenshots, page inspection, and UI verification using the playwright-cli command line tool (not an MCP). Invoke when asked to open a page, click through a flow, take a screenshot, inspect selectors, verify rendered UI, or generate a Playwright test from a recorded flow. Token-efficient: state is saved to disk and you read only what you need, instead of an MCP streaming whole accessibility trees into context.
---

# Browser automation with playwright-cli

We use Microsoft's `playwright-cli` (the `@playwright/cli` package) instead of the
Playwright MCP server. The MCP streams the full accessibility tree and screenshot bytes
into context on every step (~4x the tokens). The CLI writes that state to disk and lets
you read only the snapshot lines you need. Same browser, far cheaper context.

The webdev container already ships Playwright Chromium at `/opt/playwright-browsers`
(symlinked to `/opt/google/chrome/chrome`), so no extra browser download is needed.

## Setup

The webdev Dockerfile installs `@playwright/cli` with bun, pinned by version, so it's
already on PATH. If `playwright-cli --version` fails the image is old, and `make update`
in taproot fixes it.

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
- Screenshots: PNG files on disk, opened with the Read tool to view.

Read these files on demand rather than dumping them, which is the reason for using
the CLI over the MCP.

## Notes for this workspace

- Every app in this workspace serves on **port 8000** in dev (`make run`). The gated
  orchard sites sign in through auth.bythewood.me, so a dev run of one of them needs a
  session cookie from there or a page that isn't behind it.
- Good uses here: confirm a rendered template change, screenshot a chart/map/PDF page,
  walk a multi-step form, or record a flow to scaffold a test.

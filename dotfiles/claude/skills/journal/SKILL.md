---
name: journal
description: Wrap the current session into the git-versioned memory vault at code/memory. Invoke only when Isaac says "journal" or "memory" as a standalone instruction, or asks for something to be written down now. A background scribe records everything else, so don't invoke it after each unit of work. Writes the journal entry, updates the relevant notes and index, and commits.
---

# Journal / memory wrap

The full contract lives in `~/code/memory/CLAUDE.md`. This is the quick checklist so a wrap
is never skipped or done halfway.

## When to run

- When Isaac says "journal" or "memory" on its own, or asks for something to go in the vault
  now. Do the full wrap right away from whatever context the session has.
- Not otherwise. Hooks start a background scribe every eight messages, before a compaction and
  at session end, so capturing inline as well only writes everything twice.

## The vault

`~/code/memory` is plain Markdown in a local-only git repo with no remote, and it's the only
memory there is. `journal/` holds dated entries, `projects/` one note per project describing
how it works today, `decisions/` ADRs with a Status line, `topics/` reference articles,
`people/` profiles, and `index.md` one line per note.

## Steps

1. Append to `~/code/memory/journal/YYYY-MM-DD.md` (create it if absent) in this shape, leaving
   out any part that's empty:

   ```markdown
   ## 14:30 short title

   **Did**
   - one fact per line, a commit hash where there is one
   **Decided**
   - what was settled, and why
   **Open**
   - what's left, and who or what it waits on
   ```

   Keep lines short. Anything that needs a paragraph goes in the project or topic note.
2. Update the note the work changed so it reads as current state, rather than adding a dated
   section to it. Create a note when a durable topic or decision comes out of the work, and
   bump the Status line on an ADR a new decision amends or supersedes.
3. Add a line to `index.md` for any new note, `- [[slug]]: hook` in about 80 to 120 characters.
4. Commit, with no `Co-Authored-By` trailer:

   ```
   git -C ~/code/memory add -A && git -C ~/code/memory commit -m "memory: <short summary>"
   ```

## Conventions

- No em dashes, en dashes or semicolons.
- Frontmatter on every note: `title`, `type`, `created`, `updated`, `tags`. Filenames are
  lowercase kebab-case, journals `YYYY-MM-DD.md`, and links are `[[filename]]`.
- Turn relative dates into absolute ones.

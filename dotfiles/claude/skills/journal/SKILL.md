---
name: journal
description: Wrap the current session into the git-versioned memory vault at code/memory. Invoke when Isaac says "journal" or "memory" as a standalone instruction (the signal the session is wrapping), or after any meaningful unit of work (a task/subtask wrapping, a decision, a commit or deploy, or a real discussion worth remembering, including non-engineering ones). Writes today's journal entry, updates the relevant notes and index, and commits.
---

# Journal / memory wrap

The full, authoritative contract lives in `~/code/memory/CLAUDE.md`. Read it if you
need detail. This skill is the quick operational checklist so a wrap is never skipped
or done halfway.

## When to run

- **Trigger words.** Isaac saying "journal" or "memory" alone means the session is
  wrapping and he is moving on. Do the full wrap immediately, from whatever context
  the session has. Do not wait to be asked twice.
- **After each meaningful unit of work**, not only at session end: a task or subtask
  wrapping, a notable decision, a commit or deploy, or a real discussion (including
  non-engineering: a question answered, a topic thought through, a preference
  expressed). Capture it while fresh; do not batch the whole session into one entry.

## The vault

`~/code/memory` is plain Markdown, no database, Obsidian-compatible, **local-only git**
(no remote). It is separate from the built-in Claude auto-memory at
`~/.claude/projects/-home-dev/memory/` (terse hot facts auto-loaded every session). The
vault is the richer, narrative, version-controlled record. Layout:

```
journal/   YYYY-MM-DD.md   dated session logs: what we did/decided/discussed
projects/  one living note per workspace project: state, open threads
decisions/ ADR-style records for notable choices, with rationale
topics/    evergreen concept/reference articles
people/    profiles for the owner and recurring people
index.md   master retrieval map: one line per note
```

## Steps

1. **Append to today's journal** `~/code/memory/journal/YYYY-MM-DD.md` (create if
   absent). Add a section with a short timestamp heading covering: what we did, what we
   decided, anything discussed worth remembering, and open threads for next time.
2. **Update the relevant note** in `projects/`, `decisions/`, or `topics/` if project
   state changed or a notable choice was settled. Create a new note when a durable topic
   or decision emerges.
3. **Update `index.md`** whenever a note is *added* (one line: `- [[slug]]: one-line hook`).
4. Capture **why**, not just what; the diff and code already record what. Link related
   notes liberally with `[[wikilinks]]` (filename without extension); a link to a
   not-yet-written note is fine, it marks something worth writing later.
5. **Commit** (no `Co-Authored-By` trailer, present tense, `memory:` prefix):

   ```
   git -C ~/code/memory add -A && git -C ~/code/memory commit -m "memory: <short summary>"
   ```

## Conventions

- No em dashes or en dashes in prose; use commas, periods, colons, or parentheses.
- Frontmatter on every note: `title`, `type` (journal|project|decision|topic|person),
  `created`, `updated`, `tags`. Filenames lowercase kebab-case; journals `YYYY-MM-DD.md`.
- Convert relative dates ("next week") to absolute dates when recording.

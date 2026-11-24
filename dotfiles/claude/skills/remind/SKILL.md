---
name: remind
description: Set, list, change, run or delete reminders and scheduled checks on cron.bythewood.me, which pushes them to Isaac's phone over ntfy. Invoke whenever Isaac asks to be reminded of something, wants a birthday or anything recurring, wants something checked later or on a schedule (prices, stock, reviews, a page changing, house listings), or asks what reminders exist. Use this and never Claude's own scheduled tasks, which can't run from the VPS.
---

# Reminders with cron.bythewood.me

cron.bythewood.me is an orchard site that holds jobs and pushes them to the
`reminders` ntfy topic on Isaac's phone. Every push has a Snooze 1h button.
He can see and edit everything at https://cron.bythewood.me too.

## Calling it

The key is in `~/.claude/cron.key` and never goes in a command line you echo,
a file in a repo, or the vault.

```sh
K=$(cat ~/.claude/cron.key)
curl -s -H "Authorization: Bearer $K" https://cron.bythewood.me/api/jobs
```

| Call | What it does |
|---|---|
| `GET /api/jobs` | every job, soonest first |
| `POST /api/jobs` | create, JSON body below, answers 201 with the job |
| `GET /api/jobs/{id}` | one job |
| `PATCH /api/jobs/{id}` | change only the fields sent |
| `DELETE /api/jobs/{id}` | delete |
| `POST /api/jobs/{id}/run` | fire it now without touching its schedule, answers with the run |
| `GET /api/runs?job={id}&limit=20` | what fired and what went out |
| `GET /api/preview?cron=...` or `?at=...` | when it would fire, saves nothing |

A job is:

```json
{
  "name": "Switch 2 bundle",
  "kind": "notify",
  "at": "2026-11-22T08:00",
  "message": "Mario Kart World bundle is $499.99 today at Best Buy, Target, Walmart",
  "title": "optional, defaults to the name",
  "priority": "default",
  "link": "https://optional.button/url"
}
```

- `kind` is `notify`, which sends the message as written, or `prompt`, where the
  message is a task for Claude Haiku with web search and the push is its answer.
  A prompt job can stay quiet, so phrase a "tell me if" check as "only notify if
  ..." and it pushes nothing when the answer is no. A failed check pushes a
  "Check failed" so it never dies silently.
- Send `at` for once or `cron` for repeating, never both. A time with no offset
  is Eastern, so send `2026-11-22T08:00` and not UTC. Cron lines are five fields
  on the Eastern clock, `@daily` and friends work, and `0 9 3 3 *` is 9am every
  March 3rd. A weekday can be `thu#4` for the 4th Thursday of the month or `mon#l`
  for the last Monday, so Thanksgiving is `0 9 * 11 thu#4`.
- `priority` is `min`, `low`, `default`, `high` or `urgent`. Use `high` only when
  he asked for it to be loud, and leave the rest at default.
- A one-shot deletes itself once it lands. Pause a repeating one with
  `PATCH {"enabled": false}`.

## How to set one up

1. Work out the exact Eastern time or cron line. If the time is vague ("this
   weekend", "in the morning") pick a sensible one, morning is 8am, and say what
   you picked. Check a cron line with `/api/preview` before saving it.
2. Create it, then tell him in one line what's set and when it fires, using the
   `next` field the API returns ("Set, fires Sat Nov 22 8:00am").
3. For a birthday or anniversary make two jobs, one a week before at 9am so
   there's time for a gift and one on the day at 9am, unless he says otherwise.
4. For a check, write the prompt so it stands on its own, since it runs with no
   memory of this chat. Name the sites, what counts as worth a push, and what to
   include, then `POST /api/jobs/{id}/run` once to see it works if he's around.

Don't create a job he didn't ask for, and delete jobs instead of pausing them
when he says he's done with one.

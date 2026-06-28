---
name: roundup
description: Fast, spin-stripped news + markets briefing for Isaac, delivered as a diff since the last roundup. Invoke when Isaac says "roundup", asks "what's new / what did I miss", or wants a quick news/markets catch-up. Fans out across the political spectrum (NPR/BBC/CNN/Fox/Google News/AP/Reuters), market data (indexes/crypto/commodities), local NC, work-talk sports (NASCAR/F1/soccer), PC gaming (big releases + hyped indies), and watercooler feeds (Hacker News); filters hard to only what matters; reads the previous roundup from code/memory/roundups/ to report only what changed, then saves and commits the new one.
---

# Roundup: spin-stripped news + markets, as a diff

A roundup is a fast, skimmable briefing of what actually matters since the **last**
roundup. The whole point is the diff: how far markets moved, what developed in stories
already told, and what is genuinely new. Old news Isaac has already seen is noise.

State lives in the [[memory]] vault at `~/code/memory/roundups/`, one file per run named
`YYYY-MM-DD-HHMM.md`. Read the newest one first to get the baseline, deliver the diff,
then write and commit a fresh file. It is git-versioned so the baseline survives across
sessions and machines.

## What Isaac wants (the filter)

Only important news. Be ruthless. **Keep:** market-moving events, major political/policy,
major world events (war, elections, disasters of scale), anything touching **local NC /
Yadkin Valley / Elkin / Jonesville**, and curated sports for work talk. **Drop:** human
interest oddities (the Florida-man-eaten-by-a-croc genre), single-victim crime, celebrity
gossip, viral fluff, anything that does not move money, policy, or his actual life.

Cross-source corroboration is the importance test: if NPR + BBC + Fox + Google all lead
with it, it is real and important. If only one outlet has it and it is not local to him,
it is probably not worth a line.

**Sports caveat.** Isaac does not personally care about sports; he tracks them only to
talk with coworkers. Coworkers follow **NASCAR, F1, and soccer ("football", the World Cup
included)**. So the sports section is small and tuned to exactly those three: latest
result, next event, any standings shift. Skip US "football", MLB, NBA, etc. unless a
genuinely huge story (championship, major trade).

**Spin-stripping.** Pull the same story from across the spectrum and rewrite one neutral
line with loaded language removed (no "slams", "blasts", "destroys", no editorializing
adjectives). Then cite which sources carried it so Isaac can judge. The job is a fair,
balanced headline + one-line summary, not any outlet's framing.

## How to run it (fast = parallel fan-out)

Speed matters most. Do **not** fetch sources one at a time in the main thread. Fan out to
parallel subagents in a single message, each owning one cluster, each returning a compact
pre-filtered, spin-stripped digest (markdown bullets with sources). The main thread only
merges, dedups, computes market deltas, formats, and saves. This keeps wall-clock low and
main context clean.

### Step 0 — baseline

```bash
date '+%a %Y-%m-%d %H:%M'                       # the real timestamp for this run
ls -1 ~/code/memory/roundups/ | tail -1         # newest prior roundup (lexical sort works)
```

Read that newest file. From it grab: the prior **timestamp** (for "last roundup was N ago"),
the prior **market levels** (to compute deltas), and the **tracked stories** list (to report
developments). If the folder is empty, this is the first roundup: say so, give a full
baseline, mark nothing as a diff.

### Step 1 — fan out (one message, parallel `Agent` calls)

Give every subagent: the current time, the prior timestamp, the keep/drop filter above,
the spin-strip rule, and "report only what changed since <prior timestamp>; flag each item
[NEW] or [DEV]." Suggested clusters and good fast sources (these are RSS/JSON feeds: clean
headlines, no partisan article body; fetch with WebFetch, fall back to WebSearch or Google
News RSS if one is down):

1. **World + US + politics** (the core cross-spectrum strip)
   - NPR: `https://feeds.npr.org/1001/rss.xml`
   - BBC World: `https://feeds.bbci.co.uk/news/world/rss.xml`, BBC US/Canada: `https://feeds.bbci.co.uk/news/world/us_and_canada/rss.xml`
   - CNN top: `http://rss.cnn.com/rss/cnn_topstories.rss`
   - Fox latest: `https://moxie.foxnews.com/google-publisher/latest.xml`
   - Google News top: `https://news.google.com/rss` (and AP/Reuters surface here for a neutral anchor)
2. **Markets** (capture exact numbers for the diff)
   - Indexes (S&P 500, Nasdaq, Dow): WebSearch "S&P 500 Nasdaq Dow today" for current level + day %; reliable.
   - Crypto (BTC, ETH): `https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd&include_24hr_change=true` (fast, no key).
   - Commodities (gold, WTI crude): WebSearch "gold price WTI crude oil today".
   - One line on *why* the tape moved (Fed, CPI, earnings, geopolitics).
3. **Local NC** (Yadkin Valley / Elkin / Jonesville / Surry & Wilkes counties, NC statewide if big)
   - WebSearch "Elkin NC news", "Yadkin Valley news", "North Carolina news today". Weather only if severe (Isaac has had storm power outages).
4. **Sports for work talk** (NASCAR, F1, soccer/World Cup ONLY)
   - ESPN F1: `https://www.espn.com/espn/rss/rpm/news`, ESPN soccer: `https://www.espn.com/espn/rss/soccer/news`; NASCAR via WebSearch "NASCAR Cup last race result next race". Latest result + next event + any standings shift, one line each.
5. **Gaming** (PC gaming, big releases/announcements, hyped indies; Isaac plays PC and tracks what's new and hyped)
   - PC Gamer: `https://www.pcgamer.com/rss/`, Rock Paper Shotgun: `https://www.rockpapershotgun.com/feed`, Eurogamer: `https://www.eurogamer.net/feed`, IGN games: `https://feeds.feedburner.com/ign/games-all`.
   - Steam: `https://store.steampowered.com/feeds/news.xml`; WebSearch "Steam top sellers this week" and "most wishlisted Steam games" for what's actually hyped right now.
   - KEEP: notable new releases and firm release dates, major studio/industry news (acquisitions, engine/platform shifts, big game-changing patches), and genuinely hyped indie games (strong wishlist/early-access buzz, breakout launches). DROP: console-exclusive minutiae Isaac can't play on PC, mobile/gacha, esports match scores, routine patch notes, and review-score churn. A few bullets max, one neutral line each + (sources).
6. **Watercooler** (Hacker News only, genuinely notable items)
   - Hacker News front page: `https://hnrss.org/frontpage` (or `https://hacker-news.firebaseio.com/v0/topstories.json`). Surface only items with real signal (a major outage, a tech/industry shift, a story the mainstream feeds missed), not memes.
   - Reddit is intentionally NOT used. Tested 2026-06-27: Reddit blocks this container's datacenter IP at the network level (403/429 + "blocked by network security") on the JSON API, the `.rss` feed, old.reddit, and a full headless Chromium with a spoofed browser UA. The block is IP-based, so neither a user-agent nor a real browser bypasses it. The only working path would be the authenticated OAuth API (client_id/secret), which we have not set up. Do not waste a fetch attempt on Reddit; r/news and r/worldnews largely duplicate the mainstream feeds anyway.

Scale the fan-out to the ask: a quick "what'd I miss" can be 3 agents (news+politics,
markets, sports); a fuller catch-up after days away uses all six. Drop a cluster Isaac
says he does not want.

### Step 2 — merge and diff

Dedup the same story across clusters into one neutral line with all sources. Compute market
deltas vs the prior file (absolute + %, and direction arrows). For each prior tracked story,
either report the development [DEV] or omit it if dead. Mark genuinely new stories [NEW].
Cut anything failing the keep/drop filter.

### Step 3 — deliver (skimmable, tight)

Use markers and keep lines to one each. Lead with the diff. Example shape:

```
# Roundup — Sat Jun 27, 2:30pm   (last: 8h ago, Fri 6:00pm)

## Markets  (since last)
S&P 500  5,432  ▲0.8% (+43)   Nasdaq  17,9xx  ▲1.1%   Dow  39,xxx  ▲0.3%
BTC  $61.2k  ▼2.1%   ETH  $3.3k  ▼1.4%   Gold  $2,3xx  ▲0.4%   WTI  $79  ▲1.2%
> one line: why the tape moved.

## Top stories
- [NEW] Neutral one-line headline. (NPR, BBC, Fox)
- [DEV] Story from last time: what changed. (AP, Reuters)

## Politics
- [NEW] ... (CNN, Fox, Google)

## Local (NC / Yadkin Valley)
- ... (Elkin Tribune, WXII)

## Sports — work talk
- F1: last result / next race. (ESPN)
- NASCAR: ... (ESPN)
- Soccer: ... World Cup if live. (BBC Sport)

## Gaming
- [NEW] big release / studio news / hyped indie, one line. (PC Gamer, RPS)

## Watercooler (HN)
- ... (Hacker News)
```

If a section has nothing worth reporting, drop the whole section. Brevity over completeness.

### Step 4 — save state + commit

Write `~/code/memory/roundups/YYYY-MM-DD-HHMM.md` (timestamp from Step 0). Include a machine-
readable **Snapshot** block the next run reads as baseline, then the delivered roundup:

```markdown
---
title: Roundup 2026-06-27 1430
type: roundup
created: 2026-06-27T14:30
tags: [roundup]
---

## Snapshot (baseline for next diff)

Markets: S&P 500 5432.10 | Nasdaq 17912 | Dow 39044 | BTC 61200 (-2.1%) | ETH 3310 | Gold 2345 | WTI 79.10

Tracked stories:
- us-budget-talks: ongoing — <one-line current state>
- <slug>: ongoing|resolved — <state>

## Delivered

<the exact roundup text sent to Isaac>
```

Then commit (no `Co-Authored-By`, present tense, `memory:` prefix):

```bash
git -C ~/code/memory add -A && git -C ~/code/memory commit -m "memory: roundup YYYY-MM-DD HHMM"
```

## Notes

- Roundups are **not** indexed in `index.md` (too frequent, would churn it). The skill finds
  the latest by sorting the `roundups/` folder. `index.md` carries one static pointer line.
- No em/en dashes in prose (workspace convention). Use commas, periods, colons, parentheses.
- Times and dates from the real `date` command, not guessed.
- If a feed 404s or rate-limits, fall back to a Google News RSS topic feed or a WebSearch;
  never block the whole roundup on one dead source. Note in passing if a major source was
  unreachable.

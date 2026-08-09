# VOID 2026-08-07 - superseded by omen-3.7, do not run

Run `31122686346` was cancelled by GitHub Actions at 1h28m. **T1, T2.1-T2.4 and T3 all completed**
and landed via PR #8, merged to `main` 2026-08-07. **T4 and T5 never ran.**

What is on `main` and must not be rebuilt: `research/corpus_instances.jsonl` +
`corpus_instances.md` (**10,379 instances, 3,655 distinct symbol-days, 2024-04-02 .. 2026-07-03,
31 symbols**), `research/corpus_bar_coverage.md` (**3,595 covered symbol-days**, the denominator
T4 was going to divide by), `research/corpus_engine_entries.jsonl` + `.md` (the engine's fired
entries over all of them, via `backtest_week.simulate_day`), and **13,815 1-minute CSVs** under
`data_archive/`.

Not being resumed, and the checkboxes are deliberately left unticked: a spec whose boxes are
hand-corrected goes stale the moment the artifacts move, which is how this spec re-selected on
every push in the first place. Voiding is one edit and cannot rot.

Where the unfinished work went:

- **T4 ("What the engine cannot see")** is superseded by `specs/omen-3.7.md` **T2** and **T2.1**.
  T2 asks the same question against Austin's own 159 hand-graded marks and classifies each miss
  into a fixed vocabulary drawn from `detect_signals`' real control flow; T2.1 then reruns that
  same classifier over these 3,595 covered corpus symbol-days, so T4's question gets answered on
  T4's own data with a shared vocabulary. 3.6 already produced the headline number T4 was reaching
  for: the engine fires on **4 of 77** bars Austin grades S (`research/engine_recall.md`).
- **T5 (verdict)** is folded into `specs/omen-3.7.md` **T8**.
- **T2.1-T2.4 (bank the bars)** are superseded by `specs/omen-3.7.md` **T1**, which backfills the
  49 symbol-days Austin's marks need and adds IWM to `archive_1m.py`'s `SYMBOLS`.

# OMEN CORPUS 1.0 - the corpus as instances, not rules

status: void
version: omen-corpus-1.0
repo: aharger3/tradingbot
doc: Projects/OMEN.md

target: turn 7,805 Discord alerts into bar-anchored instances and measure how many of them the
engine sees at all - the first corpus work that produces a number about the engine rather than a
list of rules.

**Read this before touching anything, because it reverses the previous corpus strategy.**

Rule-mining from this corpus is a **settled negative**, closed 2026-08-04: 32,951 messages ->
1,568 predicate cards -> 62 grounded -> 25 distinct rules, tested over 63,520 trades, nothing beat
the engine's 38.0% WR / +0.146R. The corpus's single most-repeated rule ("close above PDH", 782
records, 18 independent restatements) tested at **32.1% / -0.038R** - the worst of the set.
Repetition frequency is anti-correlated with value here. **No row in this spec may extract,
score, or rank a rule statement.** If a row finds itself writing a predicate from prose, it has
misread the spec.

What replaced it: a rule stated out loud is the *verbalizable* part of a trader's edge, which is
the part already encoded. An **instance** - this person called this ticker at this minute - is
testable against bars and carries no such filter. Austin, 2026-08-06: *"that rule is not a rule
without context, you repeat that 3 times and it's just not even a break and retest."*

Already measured, do not recompute:

- `discord_data/*.json` holds **7,805 messages carrying a known ticker AND an intraday timestamp**
  across `scarface-alerts` (3,589), `trading-floor` (2,797), `jdub-alerts` (1,418).
  **3,758 distinct symbol-days, 2024-04-02 -> 2026-07-02.**
- **22,696 image attachments were scraped as URLs and every one is dead.** They are Discord CDN
  signed links carrying an `ex=` expiry; all sampled ones return 404, and re-resolving them via the
  Discord API returns 403 because `discord_scraper.py:82-89` authenticates with Austin's own
  logged-in browser session, not a bot. Images are therefore **out of scope for this version** and
  are the human task named in T5. Do not attempt to download them.
- Baseline, do not recompute: engine = **38.0% WR, +0.146R over 1,289 trades**
  (`research/backtest_metrics_full.json`). Its charted 12-month population is 793 trades over
  24 symbols.

Module locations: `predicates.py`, `signal_runner.py`, `backtest_12mo.py`, `polygon_feed.py` are at
the **repo root**; `levels.py` is under `research/`. Bars live in
`data_archive/<SYMBOL>/<YYYY-MM-DD>.csv`. `POLYGON_API_KEY` is in the environment. Never yfinance.

Set `PYTHONIOENCODING=utf-8` before every Python run.

## Tasks

### T1 -- Build the instance table

- model: glm

Read every `discord_data/*.json`. Each file is either a list of message objects or an id-keyed
dict of them; handle both. A message has `ts`, `content`, `author`, `attachments`, `embeds`, `id`.

Emit one row per message that has BOTH a resolvable ticker and an intraday timestamp:

- **Ticker:** an uppercase 2-5 letter token in `content` that is in the engine's traded universe.
  Take the universe from `archive_1m.py`'s `SYMBOLS` list plus `ARM`, `QCOM`, `IWM`. A message may
  name more than one - emit one row per (message, ticker) pair.
- **Timestamp:** `ts` must parse as ISO and its clock time must fall in 09:30-16:00 US/Eastern.
  Treat `ts` as already Eastern; do not shift it.

Row: `{"msg_id","channel","author","ts","day","minute_i","symbol","text","has_image"}` where
`minute_i` is minutes since 09:30 (clamp to 0-390) and `has_image` is whether any attachment or
embed URL ends in an image extension.

Write `research/corpus_instances.jsonl` and `research/corpus_instances.md` (rows per channel, per
author, distinct symbol-days, date range, and how many carry an image).

Expected scale, as a sanity check rather than a target: roughly 7,800 rows over ~3,750 distinct
symbol-days. If you produce fewer than 5,000 or more than 12,000, say so prominently in the md and
explain which filter moved.

- **done-when:** `research/corpus_instances.jsonl` has at least 5,000 lines, every line carries symbol/day/minute_i/channel/author, and `research/corpus_instances.md` states rows-per-channel and the distinct symbol-day count.

### T2.1 -- Bank the bars, shard 1 of 4

- model: glm
- depends-on: T1

The long work, split four ways so it fits the per-task ceiling and runs in parallel. **A silent gap here shrinks T4's denominator and would make the engine's recall look better than it is**, so every skipped day must be recorded with a reason, never dropped.

Read the distinct `(symbol, day)` pairs from `research/corpus_instances.jsonl`, **sort them
ascending by `(symbol, day)`**, and take only those whose zero-based position in that sorted list
satisfies `index % 4 == 0`. The sort makes the split identical across all four shards; do not
shuffle, sample, or rebalance.

For each of your pairs with no `data_archive/<SYMBOL>/<DAY>.csv`, fetch it with
`polygon_feed.fetch_day()`, which caches into that exact layout so repeat calls are free disk
reads. Measured throughput on this key is ~0.83 fetches/sec with no rate limiting, so a shard of
roughly 940 pairs runs about 19 minutes; the per-task ceiling is 25.

Write a progress line to `research/corpus_bar_fetch_1.log` every 25 pairs. On HTTP 429, back off
and retry rather than dropping the day. A day Polygon genuinely has no data for (holiday, pre-IPO,
delisted) is a legitimate skip - record it with its reason.

Write `research/corpus_bar_coverage_1.md`: pairs assigned, already cached, newly fetched, and
skipped grouped by reason.

- **done-when:** `research/corpus_bar_coverage_1.md` exists and states assigned / cached / fetched / skipped counts in its first 15 lines, and `research/corpus_bar_fetch_1.log` exists.

### T2.2 -- Bank the bars, shard 2 of 4

- model: glm
- depends-on: T1

One quarter of the bar backfill. It runs alongside the other three shards and shares nothing with them but the cache directory, which is safe because each shard owns a disjoint set of pairs.

Read the distinct `(symbol, day)` pairs from `research/corpus_instances.jsonl`, **sort them
ascending by `(symbol, day)`**, and take only those whose zero-based position in that sorted list
satisfies `index % 4 == 1`. The sort makes the split identical across all four shards; do not
shuffle, sample, or rebalance.

For each of your pairs with no `data_archive/<SYMBOL>/<DAY>.csv`, fetch it with
`polygon_feed.fetch_day()`, which caches into that exact layout so repeat calls are free disk
reads. Measured throughput on this key is ~0.83 fetches/sec with no rate limiting, so a shard of
roughly 940 pairs runs about 19 minutes; the per-task ceiling is 25.

Write a progress line to `research/corpus_bar_fetch_2.log` every 25 pairs. On HTTP 429, back off
and retry rather than dropping the day. A day Polygon genuinely has no data for (holiday, pre-IPO,
delisted) is a legitimate skip - record it with its reason.

Write `research/corpus_bar_coverage_2.md`: pairs assigned, already cached, newly fetched, and
skipped grouped by reason.

- **done-when:** `research/corpus_bar_coverage_2.md` exists and states assigned / cached / fetched / skipped counts in its first 15 lines, and `research/corpus_bar_fetch_2.log` exists.

### T2.3 -- Bank the bars, shard 3 of 4

- model: glm
- depends-on: T1

One quarter of the bar backfill. It runs alongside the other three shards and shares nothing with them but the cache directory, which is safe because each shard owns a disjoint set of pairs.

Read the distinct `(symbol, day)` pairs from `research/corpus_instances.jsonl`, **sort them
ascending by `(symbol, day)`**, and take only those whose zero-based position in that sorted list
satisfies `index % 4 == 2`. The sort makes the split identical across all four shards; do not
shuffle, sample, or rebalance.

For each of your pairs with no `data_archive/<SYMBOL>/<DAY>.csv`, fetch it with
`polygon_feed.fetch_day()`, which caches into that exact layout so repeat calls are free disk
reads. Measured throughput on this key is ~0.83 fetches/sec with no rate limiting, so a shard of
roughly 940 pairs runs about 19 minutes; the per-task ceiling is 25.

Write a progress line to `research/corpus_bar_fetch_3.log` every 25 pairs. On HTTP 429, back off
and retry rather than dropping the day. A day Polygon genuinely has no data for (holiday, pre-IPO,
delisted) is a legitimate skip - record it with its reason.

Write `research/corpus_bar_coverage_3.md`: pairs assigned, already cached, newly fetched, and
skipped grouped by reason.

- **done-when:** `research/corpus_bar_coverage_3.md` exists and states assigned / cached / fetched / skipped counts in its first 15 lines, and `research/corpus_bar_fetch_3.log` exists.

### T2.4 -- Bank the bars, shard 4 of 4

- model: glm
- depends-on: T1

One quarter of the bar backfill. It runs alongside the other three shards and shares nothing with them but the cache directory, which is safe because each shard owns a disjoint set of pairs.

Read the distinct `(symbol, day)` pairs from `research/corpus_instances.jsonl`, **sort them
ascending by `(symbol, day)`**, and take only those whose zero-based position in that sorted list
satisfies `index % 4 == 3`. The sort makes the split identical across all four shards; do not
shuffle, sample, or rebalance.

For each of your pairs with no `data_archive/<SYMBOL>/<DAY>.csv`, fetch it with
`polygon_feed.fetch_day()`, which caches into that exact layout so repeat calls are free disk
reads. Measured throughput on this key is ~0.83 fetches/sec with no rate limiting, so a shard of
roughly 940 pairs runs about 19 minutes; the per-task ceiling is 25.

Write a progress line to `research/corpus_bar_fetch_4.log` every 25 pairs. On HTTP 429, back off
and retry rather than dropping the day. A day Polygon genuinely has no data for (holiday, pre-IPO,
delisted) is a legitimate skip - record it with its reason.

Write `research/corpus_bar_coverage_4.md`: pairs assigned, already cached, newly fetched, and
skipped grouped by reason.

- **done-when:** `research/corpus_bar_coverage_4.md` exists and states assigned / cached / fetched / skipped counts in its first 15 lines, and `research/corpus_bar_fetch_4.log` exists.

### T3 -- Run the engine over those days

- model: glm
- depends-on: T2.1, T2.2, T2.3, T2.4

First merge the four shard reports `research/corpus_bar_coverage_1..4.md` into one
`research/corpus_bar_coverage.md`, summing assigned / cached / fetched / skipped and keeping the
skip reasons grouped. That merged covered count is the denominator T4 must divide by.

Then run the engine's entry detection over every covered `(symbol, day)`. Name in the report
which module and function you called - if you cannot find a single detection entry point, say so
and use whatever `backtest_12mo.py` calls internally rather than reimplementing detection.

For every entry the engine would take, record
`{"symbol","day","minute_i","direction","grade","entry","stop","target","setup"}` to
`research/corpus_engine_entries.jsonl`, where `minute_i` is minutes since 09:30.

Note the trap: in `research/*_charts.json` an `entry_i` field indexes that chart's `candles`
array, NOT minutes since 09:30. Emit `minute_i` in the minutes-since-09:30 frame so it joins
against T1, and state in the report which convention your source used and how you converted.

Write `research/corpus_engine_entries.md` with the entry count, distinct symbol-days with at least
one entry, and the grade distribution.

- **done-when:** `research/corpus_bar_coverage.md` exists with summed totals from all four shards, `research/corpus_engine_entries.jsonl` exists with one line per engine entry each carrying symbol/day/minute_i/grade, and `research/corpus_engine_entries.md` states the entry count and grade distribution.

### T4 -- What the engine cannot see

- model: glm
- depends-on: T3

The number this version exists to produce. Join `research/corpus_instances.jsonl` against
`research/corpus_engine_entries.jsonl` on `symbol|day`, matching an instance to an engine entry
when `|minute_i difference| <= 10`.

Report:

1. **Recall.** Of all instances on covered days, what fraction has an engine entry within the
   window - overall, and broken out by channel and by author. Wilson 95% intervals on each.
2. **Sensitivity to the window.** The same recall at +/-3, +/-5, +/-10 and +/-20 minutes. If recall
   barely moves between 3 and 20 minutes, the misses are real misses rather than timing offsets,
   and say so.
3. **The miss map.** Among instances with no engine entry, the distribution by symbol, by hour of
   day, and by day-of-week. Write the 300 largest-gap misses to `research/corpus_misses.jsonl`
   with their message text, so the next version has a work-list.
4. **The reverse.** Engine entries on those days that no instance sits near, by grade. An engine
   entry nobody called is not automatically wrong - report it, do not judge it.

Write `research/corpus_recall.md`, leading with the single overall recall figure and its CI.

- **done-when:** `research/corpus_recall.md` exists, its first 10 lines state overall recall with a confidence interval, it contains the four-window sensitivity table, and `research/corpus_misses.jsonl` exists with at least 100 lines.

### T5 -- Verdict

- model: opus
- depends-on: everything

Read `research/corpus_instances.md`, the merged `research/corpus_bar_coverage.md`,
`research/corpus_engine_entries.md` and `research/corpus_recall.md`. **Do not recompute any
number.**

Answer, in order:

1. **How much is the engine not seeing?** Give recall with its CI. Austin's own framing: the engine
   charts 793 trades over 12 months on 24 symbols while he expects 1-2 S setups a day, so he
   already suspects it is blind to most of the tape. Say whether this data supports that.
2. **Is the gap timing or detection?** Use the window-sensitivity table. Recall that rises sharply
   from +/-3 to +/-20 means the engine finds the setup late; flat recall means it never finds it.
3. **Where is the gap concentrated?** Name the symbols and hours carrying the misses. If it is
   concentrated in symbols outside the 24-symbol universe, that is a coverage fix, not a logic fix,
   and it is cheap - say so.
4. **Is this a filter problem or a detection problem?** OMEN 3.6 is fitting a gate to *reject*
   trades. If recall here is low, tightening a gate makes the real problem worse, and the next
   version should widen detection instead. State plainly which one the evidence supports.

Write `research/corpus_verdict.md`, ending with a `FOR AUSTIN` section of ten lines or fewer.

Its last line must be the human task, stated exactly and in full, because it is the only thing
blocking the image half of this corpus:

> Images: 22,696 chart attachments were scraped as expiring Discord CDN links and all are dead.
> `discord_scraper.py` already downloads images at scrape time (`download_images`, line 198) using
> the auth header from a logged-in Discord tab. To recover them, re-run `discord_scraper.py` on the
> Windows box while logged into Discord; images land in `discord_data/images/<channel>/`. Nothing
> else in this pipeline can do it, because the API returns 403 to a bot token.

- **done-when:** `research/corpus_verdict.md` exists, answers all four numbered questions in order, ends with a `FOR AUSTIN` section of ten lines or fewer, and its final line names the discord_scraper.py image re-run as the human task.

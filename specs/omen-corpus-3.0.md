# OMEN CORPUS 3.0 - the chat corpus was never measured

status: ready
version: omen-corpus-3.0
repo: aharger3/tradingbot
doc: Projects/CORPUS.md

target: recompute the chat-corpus recall with timestamps read as UTC instead of ET, and settle
which vision tier can read a price level off a trader's chart - the two facts that decide
whether 115,334 messages and 40,765 images are an asset or dead weight.

<!-- RUNNER: every row below needs the Windows box - 45 GB of scraped media under
     Desktop\Projects\tradingbot, 14,932 cached 1-min session CSVs under data_archive, and the
     engine itself. loop.yml is runs-on: ubuntu-latest on every job, so this spec cannot run on
     hosted Actions. It needs the-loop's local runner or a self-hosted label. Stated, not
     worked around. -->

<!-- WHY THIS VERSION EXISTS: `ts` in discord_data is naive UTC, proven by decoding Discord
     snowflakes ((id>>22)+1420070400000) - snowflake UTC matches the stored string with delta
     0.0h. The "median 13:53 ET -> 0.0% recall -> structural" verdict that retired this corpus
     read UTC as ET. The real median is 09:53 ET and 69% of instances land in ET hours 09-10,
     inside OMEN's 09:30-11:00 scan. -->


### T1 -- Stand up the omen-corpus repo and seed the taxonomy

Create a new repository at `C:\Users\aharg\Desktop\Projects\omen-corpus`. `git init` it,
add a `.gitignore` whose first lines are `data/`, `*.mp4`, `*.mkv`, `*.webm`, `*.jpg`,
`*.jpeg`, `*.png`, `*.webp` - the 45 GB of media is never committed. Do NOT add a public
remote; this is scraped paid-community content. Leave the remote unset and write the intended
private remote URL into the README instead.

Build this tree, every directory holding at least a `.gitkeep`:

```
omen-corpus/
  src/ingest/      discord.py circle.py youtube.py
  src/vision/      charts.py video.py
  src/extract/     src/normalize/
  ops/night/
  research/
  data/            (gitignored)
  CORPUS_SCHEMA.md
  taxonomy.md
  README.md
```

Seed `research/` with 15 empty jsonl files, one per category stream:
`levels`, `setups`, `rules`, `outcomes`, `risk_sizing`, `market_context`, `watchlists`,
`options`, `futures`, `psychology`, `education`, `tools`, `glossary`, `people`, `unfiled`.

`taxonomy.md` documents each of the 15 in one line and states the growth rule verbatim:
**"New information gets a new category. `unfiled.jsonl` is reviewed every version and anything
recurring in it becomes a stream of its own."**

`CORPUS_SCHEMA.md` defines the row contract every stream shares - at minimum
`source` (discord|circle|youtube), `source_id`, `ts_utc`, `ts_et`, `author`, `symbol`,
`session_date`, `category`, `payload`, `evidence` - and states the done-guard from the
2026-08-19 decision: **no row, video or day counts as done if any of its rows carries an
`error` key.**

Copy (do not move) `research/corpus_instances.jsonl`, `research/corpus_entries.jsonl`,
`research/corpus_normalized.jsonl` and `research/yt_worklist.jsonl` from `tradingbot` into
`omen-corpus/research/legacy/` so nothing in `tradingbot` breaks.

- model: deepseek
- **done-when:** `omen-corpus` is a git repo with one commit, the tree above exists, all 15
  stream files exist, `taxonomy.md` and `CORPUS_SCHEMA.md` are written, and the four legacy
  jsonl files are copied in.
- **verify:**
  ```bash
  cd /c/Users/aharg/Desktop/Projects/omen-corpus && git rev-parse HEAD
  test -f taxonomy.md && test -f CORPUS_SCHEMA.md && test -f README.md
  grep -q "New information gets a new category" taxonomy.md
  grep -q "error" CORPUS_SCHEMA.md
  test $(ls research/*.jsonl | wc -l) -eq 15
  test $(ls research/legacy/*.jsonl | wc -l) -eq 4
  head -1 .gitignore | grep -q "data/"
  git remote -v | wc -l | grep -qx 0
  ```


### T2 -- Recompute the chat-corpus recall with UTC timestamps (THE TARGET)

`research/corpus_instances.jsonl` holds 10,379 rows whose `ts` field is **naive UTC**. Prove
it first, then use it: for 50 random rows, decode the Discord snowflake in `msg_id` as
`(int(msg_id) >> 22) + 1420070400000` milliseconds and assert the resulting UTC datetime
matches the stored `ts` to within 2 seconds. If that assertion fails, stop and write the
failure - the whole version rests on it.

Then restrict to **trader-authored channels only**: `jdub-alerts`, `scarface-alerts`,
`futures-alerts`, `premarket-charts`, `swing-ideas`. Convert every `ts` from UTC to
America/New_York and keep the rows whose ET time falls in **09:30-11:00**, OMEN's scan window.

Replay the engine over those ticker-days using the existing
`ops/night/stageh_replay.py` pattern - it already wraps `backtest_week.simulate_day` and
stubs `pf.fetch_day` to return `[]` on a cache miss so the run is fully offline against
`data_archive`. Do not reimplement the engine. Reuse `stageh_score.py` for scoring.

Write `research/corpus_tz_recall.md` containing these exact lines, filled in:

```
snowflake_utc_match: 50/50
instances_total: 10379
instances_trader_channels: <n>
instances_in_et_window: <n>
ticker_days: <n>
engine_fired_days: <n>
recall_pct: <n.n>
direction_agree: <n>/<n>
prior_claimed_recall_pct: 0.0
```

- model: glm
- **done-when:** `corpus_tz_recall.md` exists with every line above filled, the snowflake check
  passed 50/50, and `recall_pct` is a real measured number rather than the 0.0 that was assumed.
- **verify:**
  ```bash
  cd /c/Users/aharg/Desktop/Projects/tradingbot
  test -s research/corpus_tz_recall.md
  grep -q "^snowflake_utc_match: 50/50$" research/corpus_tz_recall.md
  grep -Eq "^instances_in_et_window: [1-9][0-9]*$" research/corpus_tz_recall.md
  grep -Eq "^ticker_days: [1-9][0-9]*$" research/corpus_tz_recall.md
  grep -Eq "^recall_pct: [0-9]+\.[0-9]$" research/corpus_tz_recall.md
  grep -Eq "^direction_agree: [0-9]+/[0-9]+$" research/corpus_tz_recall.md
  ```


### T3 -- Vision ladder: which tier can read a price level off a chart

**An annotator already exists and it has been silently doing nothing since 2026-08-08.**
`Desktop\Scripts\scarface_image_annotator.py` sets
`IMAGES_DIR = ...\tradingbot\scarface_data\images` - **that directory does not exist.**
`list_images()` therefore returns `[]`, and the log has read
`START 0 images, 511 already done, 0 to do` on every run since (8/12, 8/14, 8/16, 8/19),
each followed by `DONE`. It reports success while touching nothing. This is the same
silent-fake-done failure as stage C's 685 fake frames, and it is the fourth instance in this
project - it is exactly what the `error`-key done-guard exists to catch, and the guard does not
catch this one because a no-op writes no rows at all. **Add a second guard: a stage that finds
zero work must exit non-zero, not log DONE.**

Its 511 existing annotations are real and worth keeping: median 561 chars, max 2,035, 462 of
511 marked `readable`, 425 carrying a price-like number, and **zero `error` keys**. But they are
`futures-alerts` 357 / `backtesting` 153 / `a-plus-setups` 1 - it ran alphabetically and stopped.
**Not one image from jdub-alerts, scarface-alerts or premarket-charts has ever been read.**
And the output is free prose, not a schema, so none of it joins to a backtest.

First action of this row: point `IMAGES_DIR` at
`C:\Users\aharg\Desktop\Projects\tradingbot\discord_data\images` (29,550 files), and make
the zero-work case exit non-zero.

Then build the sample: 200 image attachments drawn from `discord_data/images/`, stratified 100 from
`jdub-alerts`, 60 from `scarface-alerts`, 40 from `premarket-charts`, chosen by the attachment
references in those channels' json. Write the manifest to
`research/vision_pilot_manifest.jsonl` (one row per image: `path`, `channel`, `msg_id`,
`ts_utc`, `message_text`).

Run all 200 through **five tiers**, same prompt each time, asking for strict JSON:
`{ticker, direction, entry, stop, target, key_levels[], timeframe, confidence}` - and the model
must return `null` for any field it cannot actually read off the chart. Guessing is the failure
mode being tested for.

| tier | model | route |
|---|---|---|
| free | `google/gemma-4-31b-it:free` | OpenRouter |
| cheap | `qwen/qwen3.7-flash` | OpenRouter |
| batch | `google/gemini-2.5-flash-lite:batch` | OpenRouter |
| flash | `gemini-3.6-flash` | Google AI Studio, key `GOOGLE_AI_STUDIO_API_KEY` |
| incumbent | `gemini/gemini-3.1-flash-lite` | local OmniRoute, the model the existing annotator already used |

Provider pinning per the OpenRouter rules already in use. **The done-guard applies: an error
response is never written into the results file** - drop it and count it as a failure for that
tier. That is the exact bug that put 685 fake 429 rows into stage C.

Grade without a human: a tier's read of an image is **correct** when the ticker it returns
matches the ticker named in that message's text (or the filename), and when every non-null
price it returns is within 2% of the day's actual high-low range for that ticker from
`data_archive`. A price outside the day's range is a hallucination, and that is the number
that matters.

Write `research/vision_ladder.md` with one row per tier and these exact column names:

```
tier | model | n | parsed_ok | ticker_acc | price_in_range_pct | null_rate | cost_usd
```

Close with a line `WINNER: <model>` naming the cheapest tier whose `price_in_range_pct` is at
least 80.

- model: glm
- **done-when:** all five tiers ran over the same 200 images, `vision_ladder.md` holds five
  data rows plus a `WINNER:` line, no row of the results jsonl carries an `error` key, and
  `scarface_image_annotator.py` no longer points at a non-existent directory.
- **verify:**
  ```bash
  cd /c/Users/aharg/Desktop/Projects/tradingbot
  test -s research/vision_pilot_manifest.jsonl
  test $(wc -l < research/vision_pilot_manifest.jsonl) -eq 200
  test -s research/vision_ladder.md
  grep -q "price_in_range_pct" research/vision_ladder.md
  test $(grep -cE "^\| ?(free|cheap|batch|flash|incumbent) " research/vision_ladder.md) -eq 5
  ! grep -q "scarface_data" /c/Users/aharg/Desktop/Scripts/scarface_image_annotator.py
  grep -q "discord_data" /c/Users/aharg/Desktop/Scripts/scarface_image_annotator.py
  grep -qE "sys\.exit\(|raise SystemExit" /c/Users/aharg/Desktop/Scripts/scarface_image_annotator.py
  grep -qE "^WINNER: .+" research/vision_ladder.md
  ! grep -l '"error"' research/vision_ladder_results_*.jsonl
  ```


### T4 -- Re-scrape Circle with timestamps and authors

`circle_data/*/posts.json` stores posts as `{"text": ..., "images": [...]}` - **no timestamp,
no author**. An undated call cannot be backtested; this is the same failure the YouTube
`upload_date: null` bug had, and stage F is the precedent for fixing it.

Re-scrape the Circle spaces that hold posts (`a-setups` 649, `important-info` 107, `key-levels`
77, `resources` 57, `traders-lab-chat` 49, `announcements` 33), capturing `created_at`,
`author`, `post_id` and `space` alongside the existing `text` and `images`. Reuse whatever
auth path the existing Circle scraper already uses; do not build a new one. Write to
`circle_data/<space>/posts_v2.json` and leave the originals in place.

**Video and audio are out of scope for this version** - the 82 `circle_videos` and 9
`circle_audio` files wait until T3 names a vision winner.

If the scrape cannot authenticate, write `research/circle_rescrape.md` naming the exact auth
step that failed and stop - do not fabricate timestamps.

Write `research/circle_rescrape.md` with these exact lines:

```
spaces_rescraped: <n>
posts_with_ts: <n>
posts_with_author: <n>
posts_total: <n>
span_utc: <YYYY-MM-DD> -> <YYYY-MM-DD>
```

- model: deepseek
- **done-when:** every re-scraped space has a `posts_v2.json` in which every post carries a
  non-null `created_at` and `author`, and `circle_rescrape.md` reports the counts and span.
- **verify:**
  ```bash
  cd /c/Users/aharg/Desktop/Projects/tradingbot
  test -s research/circle_rescrape.md
  grep -Eq "^posts_with_ts: [1-9][0-9]*$" research/circle_rescrape.md
  grep -Eq "^span_utc: [0-9]{4}-[0-9]{2}-[0-9]{2} -> [0-9]{4}-[0-9]{2}-[0-9]{2}$" research/circle_rescrape.md
  test -s circle_data/a-setups/posts_v2.json
  python -c "import json,sys; d=json.load(open('circle_data/a-setups/posts_v2.json',encoding='utf-8')); assert d and all(p.get('created_at') and p.get('author') for p in d), 'missing ts/author'; print(len(d))"
  ```


### T5 -- Discord delta scrape, never a re-scrape

`discord_data/_state.json` carries `backfill_done: true` with `oldest`/`newest` snowflakes for
every channel. **The archive already runs to channel origin. A full re-scrape buys nothing and
risks the account.** The archive is stale from 2026-07-04 to today, roughly seven weeks.

Pull only messages newer than each channel's stored `newest` snowflake, append them to the
existing channel json, and update `newest` in `_state.json`. Attachments download to
`discord_data/images/` under the same naming the existing scraper uses.

`backfill_done` must stay `true` and `oldest` must be **byte-identical** to what it was before
this row ran - snapshot `_state.json` to `_state.before.json` as your first action so the
verify can prove it.

Write `research/discord_delta.md` with these exact lines:

```
channels_updated: <n>
new_messages: <n>
new_attachments: <n>
newest_before_utc: 2026-07-04
newest_after_utc: <YYYY-MM-DD>
oldest_unchanged: true
```

- model: deepseek
- **done-when:** new messages are appended, `newest` advances past 2026-07-04, and every
  channel's `oldest` snowflake is unchanged from `_state.before.json`.
- **verify:**
  ```bash
  cd /c/Users/aharg/Desktop/Projects/tradingbot
  test -s research/discord_delta.md
  grep -q "^oldest_unchanged: true$" research/discord_delta.md
  grep -Eq "^new_messages: [0-9]+$" research/discord_delta.md
  python -c "import json; a=json.load(open('discord_data/_state.before.json')); b=json.load(open('discord_data/_state.json')); assert all(b[k]['oldest']==v['oldest'] for k,v in a.items()), 'oldest changed'; assert all(b[k]['backfill_done'] for k in b), 'backfill flag lost'; assert any(int(b[k]['newest'])>int(a[k]['newest']) for k in a), 'nothing new'; print('ok')"
  ```


### T6 -- Video ladder: 20 videos, read the chart instead of the caption

Stage J's ceiling was *"triggers survive the caption; stops do not."* Gemini now accepts a bare
YouTube URL as `fileData.fileUri` - no download, no `yt-dlp`, no login wall. Verified
2026-08-20 against `youtu.be/sf90aJItFHw` with `gemini-3.6-flash` and key
`GOOGLE_AI_STUDIO_API_KEY`. Note `gemini-2.5-*` now 404s on that key ("no longer available to
new users"); use `gemini-3.6-flash` for the Google-direct rung.

Pick **20 videos from `research/yt_worklist.jsonl` whose captions already yielded setups** in
`corpus_entries.jsonl` - so every video has a caption-derived row to compare against. Run each
through three rungs at low media resolution: `qwen/qwen3.7-flash` (OpenRouter),
`google/gemini-2.5-flash-lite:batch` (OpenRouter), `gemini-3.6-flash` (Google direct).

Ask for the same strict JSON as T3 plus a `timestamp` for each setup, and the same rule: `null`
for anything not actually visible. Done-guard applies - error responses are dropped, never
written.

The number that decides this: **`stop_rate`, the share of setups that come back with a non-null
stop.** Captions produce stops on well under 5% of rows. If video reads do not clear that by a
wide margin, the video thread closes and the Discord charts are the only stop source.

Write `research/video_ladder.md` with a row per rung:

```
rung | model | videos | setups | stop_rate | level_agree_with_caption | cost_usd
```

Close with `CAPTION_BASELINE_STOP_RATE: <n.n>` computed from the same 20 videos' existing
caption rows, and a line `VERDICT: video beats captions` or `VERDICT: video does not beat captions`.

- model: glm
- **done-when:** three rungs ran over the same 20 videos, `video_ladder.md` holds three data
  rows, the caption baseline, and an explicit VERDICT line.
- **verify:**
  ```bash
  cd /c/Users/aharg/Desktop/Projects/tradingbot
  test -s research/video_ladder.md
  test $(grep -cE "^\| ?(qwen|batch|flash) " research/video_ladder.md) -eq 3
  grep -Eq "^CAPTION_BASELINE_STOP_RATE: [0-9]+\.[0-9]$" research/video_ladder.md
  grep -Eq "^VERDICT: video (beats|does not beat) captions$" research/video_ladder.md
  ! grep -l '"error"' research/video_ladder_results_*.jsonl
  ```


### T7 -- Let the content propose the categories it needs

- depends-on: T3, T6

Austin's instruction, verbatim: *"let videos inspire, new info needs new categories."* T1 seeded
15 streams from what was already known. This row tests them against what the chart and video
reads actually contain.

Read `research/vision_ladder_results_*.jsonl` (from T3) and `research/video_ladder_results_*.jsonl`
(from T6). These files exist because T3 and T6 wrote them - do not re-run any model call, and do
not assume anything about their contents beyond the JSON schema those rows named.

Classify every extracted item into one of T1's 15 streams. Anything that fits none of them goes
to `unfiled`. Then cluster the `unfiled` items and propose new categories: a cluster earns a
stream when it holds **at least 10 items from at least 3 distinct sources**, the same
distinct-source bar the corpus already uses for rule candidates.

Write `research/taxonomy_v2.md` with:

```
items_classified: <n>
items_unfiled: <n>
clusters_found: <n>
categories_proposed: <n>
```

followed by one section per proposed category giving its name, a one-line definition, its item
count, its distinct-source count, and three verbatim example items. Append the proposed
categories to `omen-corpus/taxonomy.md` under a `## Proposed - awaiting approval` heading; do
not create their jsonl files, that is Austin's call.

- model: glm
- **done-when:** every item from both ladders is classified, `taxonomy_v2.md` reports the four
  counts and details each proposal, and `omen-corpus/taxonomy.md` carries a
  `## Proposed - awaiting approval` section.
- **verify:**
  ```bash
  cd /c/Users/aharg/Desktop/Projects/tradingbot
  test -s research/taxonomy_v2.md
  grep -Eq "^items_classified: [1-9][0-9]*$" research/taxonomy_v2.md
  grep -Eq "^categories_proposed: [0-9]+$" research/taxonomy_v2.md
  grep -q "## Proposed - awaiting approval" /c/Users/aharg/Desktop/Projects/omen-corpus/taxonomy.md
  ```


### T8 -- TradingView Remix: build the harness, name the human step

- depends-on: everything

`tvremix.xyz` is an official TradingView AI copilot with a remote MCP server at
`https://tvremix.xyz/api/mcp/v1` (OAuth 2.1) and a Claude Code plugin
(`claude plugin marketplace add tvremix/claude-plugin`, then `claude plugin install tvremix`).
Free public beta; limits scale with the TradingView tier and **Austin has Premium = 5x**.

It serves quotes, fundamentals, multi-timeframe indicators, options chains, and **automated SMC
structure: BOS/CHoCH, order blocks, FVGs, liquidity pools, premium/discount zones** - exactly
the detector family OMEN cannot emit and that Stage K failed to rebuild from pivots.

**The OAuth connect is a human action and this row must not attempt it.** Build everything that
sits around it and stop at the door:

1. `src/vision/tvremix_eval.py` in `omen-corpus` - takes a list of `(ticker, session_date)`
   pairs, calls the MCP's level/structure tools, and writes one jsonl row per day of the
   order blocks, FVGs and key levels it returns.
2. `research/tvremix_eval_plan.md` - the comparison design: which corpus ticker-days to run
   (draw them from `research/corpus_backtest_manifest.jsonl`, which already holds 701 replayable
   rows over 225 ticker-days), and how a TV-returned order block is scored against the level the
   trader actually called. Reuse the distinct-videos / distinct-sources bar already in this
   project rather than inventing a new one.
3. `research/tvremix_setup.md` - the exact click path for Austin: install the plugin, add the
   custom connector, authorize, and the one command that proves it is connected.

State plainly in the eval plan that TradingView **cannot** replace the cached bar archive: an
MCP is a live request/response tool, not a bulk historical feed, and it cannot serve the 14,932
cached 1-min session-days the backtests run on. Its value is as a level source and structure
oracle. Market data stays TastyTrade-only per OMEN Settled 8/19 item 4.

- model: deepseek
- **done-when:** the harness and both markdown files exist, the harness imports cleanly without
  network access, and `tvremix_setup.md` names the OAuth authorize step as the one thing only
  Austin can do. This row's done-when is the blocked human step - the run finishes and the
  notification names it.
- **verify:**
  ```bash
  cd /c/Users/aharg/Desktop/Projects/omen-corpus
  test -s src/vision/tvremix_eval.py
  python -c "import ast,sys; ast.parse(open('src/vision/tvremix_eval.py',encoding='utf-8').read()); print('parses')"
  test -s research/tvremix_eval_plan.md
  test -s research/tvremix_setup.md
  grep -q "corpus_backtest_manifest.jsonl" research/tvremix_eval_plan.md
  grep -qi "cannot replace" research/tvremix_eval_plan.md
  grep -qi "authorize" research/tvremix_setup.md
  ```

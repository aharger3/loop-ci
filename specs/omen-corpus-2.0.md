# OMEN CORPUS 2.0 - the chart, not the words

status: done
version: omen-corpus-2.0
repo: aharger3/tradingbot
doc: Projects/OMEN-CONSOLIDATED.md

target: finish the recall number corpus 1.0 never computed, then prove whether a vision model
reading frames off Scarface and JDub videos can produce bar-anchored instances accurately enough
to be worth grinding the full catalogue.

**Read this before touching anything.**

Text mining this corpus is a **settled negative**, closed 2026-08-04: 32,951 messages -> 1,568
predicate cards -> 25 distinct rules, tested over 63,520 trades, nothing beat the engine's
38.0% WR / +0.146R, and the single most-repeated rule tested worst of the set. Corpus 1.0 then
established why: a rule a trader can state out loud is the *verbalizable* part of the edge, which
is the part already encoded. **No row in this spec may extract, score, or rank a rule statement
from prose, a transcript, or a caption.** If a row finds itself writing a predicate from words,
it has misread the spec.

What this version mines instead is the **chart that was on screen**. A frame from a trading video
carries the ticker and timeframe in the chart header, the clock on the x-axis, and the price levels
the trader drew. Those four things convert a video into an *instance* - this person pointed at this
ticker at this minute at these prices - which is the same artifact corpus 1.0 built from Discord and
the only one that has never been mined. An instance is testable against bars. A sentence is not.

**The self-check that makes this trustworthy:** every extracted price level is tested against the
real Polygon bars for that symbol-day. A frame the model misread produces levels that do not sit
inside that day's actual range. T4 measures that pass rate. This version reports the number; it does
not decide anything on it.

Already measured by corpus 1.0, on main. Do not recompute any of it:

- `research/corpus_instances.jsonl` - **10,379 Discord instances**, 3,655 distinct symbol-days,
  2024-04-02 -> 2026-07-03. scarface-alerts 4,020 / jdub-alerts 3,080 / trading-floor 2,757.
- `research/corpus_engine_entries.jsonl` - **417 engine entries on 380 distinct symbol-days**,
  from `backtest_week.simulate_day`, `minute_i` already in the minutes-since-09:30 frame.
- `research/corpus_bar_coverage.md` - **3,595 covered symbol-days** of 1-minute bars, banked in
  `data_archive/<SYMBOL>/<YYYY-MM-DD>.csv` and committed. That 3,595 is the denominator.
- Engine baseline: **38.0% WR, +0.146R over 1,289 trades**. Never recompute it.

The two channels are `https://www.youtube.com/@ScarfaceTrades` and
`https://www.youtube.com/@jdubtrades`. Scarface posts as TonyMontana in Discord.

Runner facts: ubuntu-latest, ffmpeg preinstalled, `POLYGON_API_KEY` in the environment, 25 minutes
per task. `yt-dlp` is NOT installed - any row that needs it runs `python3 -m pip install --quiet
yt-dlp` first. Set `PYTHONIOENCODING=utf-8` before every Python run. Module locations:
`predicates.py`, `signal_runner.py`, `backtest_12mo.py`, `backtest_week.py`, `polygon_feed.py` at
the repo root; `levels.py` under `research/`. Never yfinance.

Do not commit video files, frame images, or thumbnails. `*.mp4` is already gitignored; delete
extracted frames before the task ends. Only JSONL and markdown belong in the commit.

## Tasks

### [x] T1 -- The recall number corpus 1.0 never produced

- model: glm

Corpus 1.0 banked every ingredient for this and then died before the join. It is the cheapest
unclaimed number on the board, so it runs first and independently of everything else here.

Join `research/corpus_instances.jsonl` against `research/corpus_engine_entries.jsonl` on
`symbol|day`, counting an instance as *seen* when an engine entry exists on the same symbol-day
within a window of `minute_i`. Restrict the population to instances whose symbol-day appears in the
covered set - a day with no bars was never offered to the engine and must not count against it.
Take the covered set from the symbol-days present under `data_archive/`, and state in the report how
many instances that restriction dropped.

Report, in `research/corpus_recall.md`:

1. **Recall.** Of covered instances, the fraction with an engine entry within +/-10 minutes -
   overall, then broken out by channel and by author. Wilson 95% intervals on each.
2. **Window sensitivity.** The same recall at +/-3, +/-5, +/-10 and +/-20 minutes. If recall barely
   moves from 3 to 20, the misses are real misses and not timing offsets. Say which it is.
3. **The miss map.** Among unseen instances, the distribution by symbol, by hour, and by weekday.
   Write the 300 misses on the highest-instance-count symbol-days to `research/corpus_misses.jsonl`
   with their message text, so a later version has a work-list.
4. **The reverse.** Engine entries no instance sits near, by grade. An entry nobody called is not
   automatically wrong - report it, do not judge it.

Lead the file with the single overall recall figure and its interval.

- **done-when:** `research/corpus_recall.md` exists, its first 10 lines state overall recall with a confidence interval, it contains the four-window sensitivity table, and `research/corpus_misses.jsonl` exists with at least 100 lines.

### [x] T2 -- Enumerate both channels, and find out what this runner can actually fetch

- model: glm

Two jobs: build the work-list, then establish honestly what a GitHub Actions IP can pull from
YouTube. The second job matters more than it looks - datacenter IPs are known to get SABR 403 on
video streams and empty timedtext on anonymous captions, and every later row branches on the answer.
**A probe that fails is a successful probe.** Report the wall precisely; do not work around it, do
not retry with credentials, and do not treat a block as a task failure.

Install yt-dlp, then enumerate both channels' full video tabs with `--flat-playlist`, which is a
plain web request and is expected to work. For every video emit one line to
`research/yt_worklist.jsonl`: `{"video_id","channel","title","duration_s","upload_date"}` where
channel is `scarface` or `jdub`. Sort the file by `video_id` so every later shard splits it
identically.

Then probe, on one video of at least 5 minutes, each of these separately and record the exact exit
code and the last line of stderr for each:

- video stream, capped small: `-f "bv*[height<=720]/b[height<=720]" --no-playlist`
- automatic captions only: `--write-auto-subs --sub-langs en --skip-download`
- the still thumbnail, by plain HTTPS GET to `https://i.ytimg.com/vi/<id>/maxresdefault.jpg`, with
  `hqdefault.jpg` as the fallback. This one is an ordinary image CDN and should survive whatever
  blocks the others.

Delete anything you downloaded. Write `research/yt_probe.md` whose **first 15 lines are a table with
one row per probe: name, worked yes/no, exit code, error**. The rest of the file may explain. The
last line of the file must read `FRAME SOURCE: video` if the video stream downloaded, or
`FRAME SOURCE: thumbnail` if it did not - later rows read exactly that line and nothing else.

- **done-when:** `research/yt_worklist.jsonl` has at least 200 lines each carrying video_id and channel, and `research/yt_probe.md` exists whose first 15 lines are a per-probe table with exit codes and whose final line reads either `FRAME SOURCE: video` or `FRAME SOURCE: thumbnail`.

### T3.1 -- Read the charts, shard 1 of 3

- model: opus
- depends-on: T2

Vision extraction. This is the row the whole version exists to test, and it runs on opus because it
reads images.

Read the last line of `research/yt_probe.md` to learn the frame source. Read
`research/yt_worklist.jsonl`, sort ascending by `video_id`, keep those whose zero-based position in
that sorted list satisfies `index % 3 == 0`, drop any shorter than 180 seconds, and **process the
first 6 of what remains**. Six, not more: the task ceiling is 25 minutes and this version is proving
the method, not grinding the catalogue. State in your report which six you took.

Getting frames, by source:

- `video` - download at `-f "bv*[height<=720]/b[height<=720]"`, then
  `ffmpeg -i <in> -vf fps=1/60 -q:v 3 -frames:v 15 frames/%03d.jpg`. At most 15 frames per video.
- `thumbnail` - fetch `https://i.ytimg.com/vi/<id>/maxresdefault.jpg`, falling back to
  `hqdefault.jpg`. One frame per video. This is a degraded mode and the report must say so.

Then read the frames with your Read tool, at most 6 images per turn, and emit one JSON line per
frame to `research/yt_instances_1.jsonl`:

```
{"video_id","channel","t_sec","source","has_chart","symbol","chart_date","date_source",
 "clock_et","timeframe","price_levels","annotations","confidence"}
```

- `symbol` from the chart header, uppercase, or null if not legible. Never guess it from the title.
- `chart_date` as `YYYY-MM-DD`. If the date is legible on the chart use it and set `date_source` to
  `chart`. If only a time is visible, fall back to the video's `upload_date` and set `date_source`
  to `upload`. If neither, null. **The distinction is the whole point of the field** - T4 measures
  the two sources separately, so never label an upload-date guess as a chart read.
- `clock_et` as `HH:MM` from the x-axis at the point of interest, or null.
- `price_levels` - every horizontal price the trader has drawn or that the chart marks as an entry,
  stop or target, read off the y-axis as plain numbers. Empty list if none.
- `annotations` - short tags for what is marked on the frame, drawn from `order block`, `entry`,
  `stop`, `target`, `break`, `retest`, `level`, `no chart`. Tags describe what is *drawn*, not what
  is being argued.
- `confidence` 0.0 to 1.0, your own read quality for that frame.

**Do not summarise, paraphrase, or interpret what the trader is saying.** No transcript, no caption,
no strategy prose anywhere in the output. A row that emits an opinion has misread this spec.

Write `research/yt_frames_1.md` stating videos taken, frames read, rows emitted, how many carried a
symbol, and how many carried a chart-read date. If the frame source is `thumbnail`, say plainly in
the first five lines that this shard ran degraded and one frame per video is all it had.

- **done-when:** `research/yt_instances_1.jsonl` exists with one JSON line per frame read, every line carrying video_id, source, has_chart and confidence, and `research/yt_frames_1.md` states videos taken, frames read, rows emitted, and the symbol and chart-date counts.

### T3.2 -- Read the charts, shard 2 of 3

- model: opus
- depends-on: T2

Identical to shard 1 but for the split and the output filenames. It shares nothing with the other
shards except the work-list, which each shard reads and splits identically.

Read the last line of `research/yt_probe.md` to learn the frame source. Read
`research/yt_worklist.jsonl`, sort ascending by `video_id`, keep those whose zero-based position in
that sorted list satisfies `index % 3 == 1`, drop any shorter than 180 seconds, and **process the
first 6 of what remains**. State in your report which six you took.

Getting frames, by source:

- `video` - download at `-f "bv*[height<=720]/b[height<=720]"`, then
  `ffmpeg -i <in> -vf fps=1/60 -q:v 3 -frames:v 15 frames/%03d.jpg`. At most 15 frames per video.
- `thumbnail` - fetch `https://i.ytimg.com/vi/<id>/maxresdefault.jpg`, falling back to
  `hqdefault.jpg`. One frame per video, and the report must say it ran degraded.

Read the frames with your Read tool, at most 6 images per turn, and emit one JSON line per frame to
`research/yt_instances_2.jsonl` using exactly the schema and the field rules given in shard 1:
`{"video_id","channel","t_sec","source","has_chart","symbol","chart_date","date_source","clock_et","timeframe","price_levels","annotations","confidence"}`.
`symbol` comes from the chart header and never from the title. `date_source` is `chart` only when
the date was legible on the chart itself, `upload` when you fell back to the video's upload date.

**Do not summarise, paraphrase, or interpret what the trader is saying.** No transcript, no caption,
no strategy prose anywhere in the output.

Write `research/yt_frames_2.md` stating videos taken, frames read, rows emitted, how many carried a
symbol, and how many carried a chart-read date.

- **done-when:** `research/yt_instances_2.jsonl` exists with one JSON line per frame read, every line carrying video_id, source, has_chart and confidence, and `research/yt_frames_2.md` states videos taken, frames read, rows emitted, and the symbol and chart-date counts.

### T3.3 -- Read the charts, shard 3 of 3

- model: opus
- depends-on: T2

Identical to shard 1 but for the split and the output filenames. It shares nothing with the other
shards except the work-list, which each shard reads and splits identically.

Read the last line of `research/yt_probe.md` to learn the frame source. Read
`research/yt_worklist.jsonl`, sort ascending by `video_id`, keep those whose zero-based position in
that sorted list satisfies `index % 3 == 2`, drop any shorter than 180 seconds, and **process the
first 6 of what remains**. State in your report which six you took.

Getting frames, by source:

- `video` - download at `-f "bv*[height<=720]/b[height<=720]"`, then
  `ffmpeg -i <in> -vf fps=1/60 -q:v 3 -frames:v 15 frames/%03d.jpg`. At most 15 frames per video.
- `thumbnail` - fetch `https://i.ytimg.com/vi/<id>/maxresdefault.jpg`, falling back to
  `hqdefault.jpg`. One frame per video, and the report must say it ran degraded.

Read the frames with your Read tool, at most 6 images per turn, and emit one JSON line per frame to
`research/yt_instances_3.jsonl` using exactly the schema and the field rules given in shard 1:
`{"video_id","channel","t_sec","source","has_chart","symbol","chart_date","date_source","clock_et","timeframe","price_levels","annotations","confidence"}`.
`symbol` comes from the chart header and never from the title. `date_source` is `chart` only when
the date was legible on the chart itself, `upload` when you fell back to the video's upload date.

**Do not summarise, paraphrase, or interpret what the trader is saying.** No transcript, no caption,
no strategy prose anywhere in the output.

Write `research/yt_frames_3.md` stating videos taken, frames read, rows emitted, how many carried a
symbol, and how many carried a chart-read date.

- **done-when:** `research/yt_instances_3.jsonl` exists with one JSON line per frame read, every line carrying video_id, source, has_chart and confidence, and `research/yt_frames_3.md` states videos taken, frames read, rows emitted, and the symbol and chart-date counts.

### T4 -- Test every chart read against the real bars

- model: glm
- depends-on: T3.1, T3.2, T3.3

The falsifiability pass, and the reason this version can be trusted where a transcript pipeline could
not. A frame the model misread produces price levels that do not sit inside that symbol-day's actual
range. **This row is a measurement, not a gate.** Report the numbers plainly and let T5 read them.
Never delete, filter or re-run a shard to improve a rate.

Merge `research/yt_instances_1.jsonl`, `_2` and `_3` into `research/yt_instances.jsonl`, preserving
every row including the ones with no symbol.

For each merged row carrying both a symbol and a chart_date, load
`data_archive/<SYMBOL>/<CHART_DATE>.csv`. When the file is absent, fetch it with
`polygon_feed.fetch_day()`, which caches into that exact layout. A day Polygon has no bars for
(weekend, holiday, pre-IPO, delisted) is a legitimate outcome - record it as `no_bars`, never as a
misread.

Classify every row into exactly one bucket and count them:

- `no_symbol` - no symbol was read
- `no_date` - symbol but no date
- `no_bars` - symbol and date, but Polygon has no session
- `verified` - every price in `price_levels` falls inside `[day_low * 0.98, day_high * 1.02]`, and
  `price_levels` is non-empty
- `out_of_range` - at least one price falls outside that band
- `no_levels` - symbol, date and bars, but nothing was drawn to check

Write verified rows to `research/yt_instances_verified.jsonl`, each carrying an added `minute_i`
computed from `clock_et` as minutes since 09:30, clamped to 0-390, and null when `clock_et` is null.

Then run the same join T1 ran, so the video instances get the same treatment the Discord ones did:
of verified rows with a `minute_i`, what fraction has an engine entry on that symbol-day within
+/-10 minutes.

Write `research/yt_verification.md` leading with the overall verified rate as a percentage of rows
that had both a symbol and a date. Break that rate out by `date_source`, because a chart-read date
and an upload-date guess are different claims and pooling them hides which one works. Also break it
out by `confidence` band and by shard. Close with the engine-recall figure for verified video
instances.

- **done-when:** `research/yt_instances.jsonl` and `research/yt_instances_verified.jsonl` both exist, and `research/yt_verification.md` states in its first 12 lines the overall verified rate and the counts in all six buckets, and contains the verified rate broken out by date_source.

### T5 -- Verdict

- model: opus
- depends-on: everything

Read `research/corpus_recall.md`, `research/yt_probe.md`, `research/yt_verification.md` and the
three `research/yt_frames_*.md`. **Do not recompute any number and do not open the JSONL files.**

Answer, in order:

1. **How much of the tape is the engine blind to?** Give recall with its interval. Austin's own
   framing: the engine charts 793 trades over 12 months on 24 symbols while these two called
   thousands of setups, so he already suspects it sees almost nothing. Say whether the data supports
   that, and say it as a number.
2. **Is the gap timing or detection?** Use the window-sensitivity table. Recall rising sharply from
   +/-3 to +/-20 means the engine finds the setup late; flat recall means it never finds it at all.
3. **Is this a filter problem or a detection problem?** OMEN 3.6 is fitting a gate to *reject*
   trades. If recall is low, tightening a gate makes the real problem worse and the next version
   should widen detection instead. State plainly which one the evidence supports.
4. **Did the vision read work?** Give the verified rate and the chart-date-versus-upload-date split.
   Say what actually limited it - the frame source, the frame rate, the chart style, the number of
   videos, or the model's read - and be specific about which, because the fix differs for each.
5. **Is the full-catalogue grind worth building?** Corpus 2.1 would add a drain-then-stop loop to
   `loop.yml` that re-dispatches itself until the work-list is empty, and grind all of both channels
   at roughly 18 videos per pass. Recommend for or against, with the verified rate as your reason,
   and name the one change most likely to raise that rate. This is a recommendation from measured
   state, never an assertion that the project should stop - Austin is committed long-term and there
   is no kill gate here.

Write `research/corpus_2_verdict.md`, ending with a `FOR AUSTIN` section of ten lines or fewer whose
first line is the single most important number in the whole run.

- **done-when:** `research/corpus_2_verdict.md` exists, answers all five numbered questions in order, and ends with a `FOR AUSTIN` section of ten lines or fewer.

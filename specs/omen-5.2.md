# OMEN 5.2 - Exit lab and engine-accuracy scorecard

status: ready
version: omen-5.2
repo: aharger3/tradingbot
doc: Projects/OMEN.md

target: turn Austin's 184 hand marks into two numbers he does not have - what a scale-out
exit policy earns per year, and whether the engine's grades agree with his eyes.

Context the rows need and cannot infer:

- Austin graded **both 5.2 decks**. 120 day cards (TSLA 60, QQQ 30, SPY 30) and **64 trade
  marks** with entry / stop / exit bar indices and an `r_multiple`.
- **The `r_multiple` on a mark is tranche 1 only.** He took **30-50% of contracts off at
  high-of-day** and let the rest run unmarked. Mean tranche-1 R is +1.24, win rate 87%,
  median hold 2-3.5 minutes. Do **not** read 1.24R as the trade's full result - the runner is
  missing from the data and reconstructing it is the point of this version.
- His stated target is **2:1 average over a year**, not per trade.
- Scale-out shapes to test: **30/30/30/10** when the trade is trending, **50/20/20/10**
  when it is not.
- Trending, in his words: the index (QQQ/SPY) is healthy and moving the *same direction*
  as the trade, the stock is making higher highs (lower lows on shorts), and the entry is
  **early** in the window.
- Runner rule: after tranche 1, stop to break-even, trail, **flat by 11:00 ET** and earlier
  if structure breaks or the tape goes to consolidation.
- Causal stand-in for "exit at HOD": price makes a **new high-of-day after entry**, then
  tranche 1 comes off at the **close of the first bar that fails to make a higher high**
  (mirror for shorts). No look-ahead anywhere in the lab.

The mark files are committed in this repo at `specs/data/omen-5.2/` and are public.

---

### T1 -- Ingest the 184 marks and write the path map every other row reads

- model: deepseek

Fetch both mark files into the tradingbot repo:

```
https://raw.githubusercontent.com/aharger3/loop-ci/main/specs/data/omen-5.2/deck_marks_index_2026-08-19.jsonl
https://raw.githubusercontent.com/aharger3/loop-ci/main/specs/data/omen-5.2/deck_marks_tsla_2026-08-20.jsonl
```

Write them to `research/marks/` unchanged. Then write **two** files.

`research/marks_summary.md` - counts and sanity checks, and it must contain these exact
lines with the real numbers filled in:

```
day_cards: 120
trade_marks: 64
tranche1_mean_r: <number>
tranche1_win_rate: <number>
```

`research/v52_paths.md` - **the discovery file. Later rows are fresh contexts and can only
learn the repo from this file.** It must name, one per line, with real repo-relative paths
that exist:

```
bars_loader: <module.function that returns 1-min OHLCV for a symbol+date>
bars_cache: <directory holding the 1-min cache>
backtest_trades: <file holding the 1,289 backtest trades>
grade_fn: <module.function that assigns S/A/B/C grades to a signal>
```

Verify each path exists before writing it. A guessed path strands four rows.

- **done-when:** both jsonl files are in `research/marks/`, `research/marks_summary.md`
  carries the four lines above, and every path named in `research/v52_paths.md` exists on
  disk.
- **verify:**
  ```bash
  test -s research/marks/deck_marks_tsla_2026-08-20.jsonl
  test -s research/marks/deck_marks_index_2026-08-19.jsonl
  grep -q "^day_cards: 120$" research/marks_summary.md
  grep -qE "^trade_marks: 64$" research/marks_summary.md
  grep -qE "^tranche1_mean_r: [0-9.]+" research/marks_summary.md
  grep -qE "^bars_loader: .+" research/v52_paths.md
  grep -qE "^backtest_trades: .+" research/v52_paths.md
  python -c "import re,os,sys; [sys.exit('missing '+p) for p in re.findall(r'^(?:bars_cache|backtest_trades): (.+)$', open('research/v52_paths.md').read(), re.M) if not os.path.exists(p.strip())]"
  ```

### T2 -- Score the engine against Austin's 120 graded days

- model: glm
- depends-on: T1

Read `research/v52_paths.md` for the bar loader, the grader and the backtest trade file.
Read the day cards from `research/marks/`.

For every one of the 120 graded days, ask what the engine did on that day and compare:

1. **Day-level agreement.** Austin's grade is `S`, `A`, `C` or `none`. Treat `S`/`A` as
   "there was a trade here". Compute precision and recall of the engine's own signal-days
   against that label, per symbol and overall.
2. **Entry-level agreement.** For each of the 64 trade marks, did the engine fire a signal
   on that day within **+/- 3 bars** of his `entry_i`, same side? Report the match rate and
   the median bar offset (engine bar minus his bar) - a consistent positive offset means
   the engine is late, which is a different defect than being blind.
3. **The 36 TSLA `none` days.** How many did the engine fire on? Those are false positives
   against a human who looked and refused.

Write `research/v52_engine_scorecard.md`, with these exact lines:

```
day_precision: <0-1>
day_recall: <0-1>
entry_match_rate: <0-1>
median_bar_offset: <integer, engine minus Austin>
false_fires_on_none_days: <integer>
```

Then a short section in plain English on what the numbers mean for the S grade.

- **done-when:** `research/v52_engine_scorecard.md` exists with all five lines filled from
  real computation over all 120 cards and all 64 marks.
- **verify:**
  ```bash
  grep -qE "^day_precision: 0?\.[0-9]+|^day_precision: [01]$" research/v52_engine_scorecard.md
  grep -qE "^day_recall: " research/v52_engine_scorecard.md
  grep -qE "^entry_match_rate: " research/v52_engine_scorecard.md
  grep -qE "^median_bar_offset: -?[0-9]+$" research/v52_engine_scorecard.md
  grep -qE "^false_fires_on_none_days: [0-9]+$" research/v52_engine_scorecard.md
  ```

### T3 -- Build the exit lab

- model: glm
- depends-on: T1

Read `research/v52_paths.md` for the bar loader and cache.

Write `research/exit_lab.py`. It takes a list of trades - each one an entry bar index, a
stop price, a side, a symbol and a date - and replays **exit policies** over the 1-min bars,
returning realised R per trade per policy. Entry and stop are **fixed inputs**; only the
exit varies. No look-ahead: a policy may only read bars at or before the bar it acts on.

Policies to implement, all with tranche weights summing to 1.0:

| id | tranche 1 | rest |
|---|---|---|
| `flat_1r` | 100% at 1.0R | - |
| `flat_2r` | 100% at 2.0R | - |
| `hod_only` | 100% at the causal-HOD rule | - |
| `30_30_30_10` | 30% causal-HOD | 30% / 30% / 10%, stop to BE after tranche 1, trail |
| `50_20_20_10` | 50% causal-HOD | 20% / 20% / 10%, stop to BE after tranche 1, trail |

**Causal-HOD rule:** after entry, wait for a bar whose high exceeds every high since 09:30;
tranche 1 exits at the **close of the first subsequent bar that does not make a higher
high**. Mirror for shorts. If no new HOD prints before the clock, tranche 1 exits at the
clock along with the rest.

**Runner rule, shared by both scale-out policies:** stop moves to entry after tranche 1;
remaining tranches exit on a trail (test both **1.0x ATR14** and **prior-bar low/high**);
force flat at **11:00 ET**; force flat early on a **structure break** (a lower low on longs,
higher high on shorts, against the trade) or on **consolidation** (no new extreme in the
trade's direction for 5 consecutive bars).

Include a `--selftest` mode that runs the lab over the 64 marks and asserts the causal-HOD
exit bar lands within **5 bars** of Austin's own marked `exit_i` on at least **half** of
them. That is the calibration check - if the rule cannot approximate what his eye did, the
whole lab is measuring something else, and the selftest must fail loudly rather than pass.

Write the calibration result to `research/exit_lab_calibration.md` including the line:

```
hod_rule_within_5_bars: <0-1>
```

- **done-when:** `research/exit_lab.py --selftest` exits 0 and the calibration file reports
  the agreement fraction against all 64 marks.
- **verify:**
  ```bash
  python research/exit_lab.py --selftest
  grep -qE "^hod_rule_within_5_bars: 0?\.[0-9]+" research/exit_lab_calibration.md
  ```

### T4 -- Build the trend gate and check it against his day_type labels

- model: glm
- depends-on: T1

Read `research/v52_paths.md` for the bar loader.

Write `research/trend_gate.py` exposing `is_trending(symbol, date, entry_i, side) -> bool`
computed **only from bars at or before `entry_i`**, from three components:

1. **Index alignment** - QQQ (for TSLA and QQQ trades) or SPY (for SPY trades) is moving the
   same direction as the trade from 09:30 to `entry_i`, by a margin you pick and document.
2. **Structure** - the traded symbol has made higher highs *and* higher lows on the 1-min
   bars since 09:30 (mirror for shorts).
3. **Earliness** - `entry_i` is at or before **09:50 ET**.

Trending = at least **2 of 3**. Document the exact thresholds at the top of the file.

Austin tagged `day_type` (`trend` / `chop` / `range` / `reversal` / blank) on the graded
days. Score the gate against those labels - `trend` is trending, `chop` and `range` are not,
`reversal` is excluded from the agreement count. Write `research/trend_gate_agreement.md`
with the exact line:

```
gate_vs_austin_agreement: <0-1>
```

plus a table of every disagreeing day with the three component values, so the next version
can see *which* component is wrong rather than re-tuning blind.

- **done-when:** the gate runs on every marked day and the agreement file names each
  disagreement with its three components.
- **verify:**
  ```bash
  python -c "import research.trend_gate as g; assert callable(g.is_trending)"
  grep -qE "^gate_vs_austin_agreement: 0?\.[0-9]+" research/trend_gate_agreement.md
  ```

### T5 -- Run every policy over both corpora and report the yearly average

- model: glm
- depends-on: T3, T4

Read `research/v52_paths.md` for the backtest trade file. Import `research/exit_lab.py` and
`research/trend_gate.py` - do not reimplement either.

Run all five policies from T3, plus a sixth, **`adaptive`**: use `trend_gate.is_trending`
to pick `30_30_30_10` when trending and `50_20_20_10` when not.

Run them over **two** corpora, kept separate in the output:

- **A: Austin's 64 marked entries** - his entry bar, his stop, machine exits.
- **B: the engine's backtest trades** from the path map - the engine's entries and stops,
  machine exits. This is the corpus that carries a year, so it owns the yearly number.

Write `research/v52_scaleout_results.md` with one table per corpus - policy, mean R, median
R, win rate, worst trade, max consecutive losers, and **mean R annualised at the corpus's
own trade rate**. Then these exact lines, taken from corpus B:

```
best_policy: <policy id>
best_policy_mean_r: <number>
adaptive_mean_r: <number>
baseline_flat_1r_mean_r: <number>
```

Also dump the per-trade results to `research/v52_scaleout_results.json` so 5.3 does not have
to recompute.

- **done-when:** both corpora are reported for all six policies and the four lines above are
  present and numeric.
- **verify:**
  ```bash
  grep -qE "^best_policy: (flat_1r|flat_2r|hod_only|30_30_30_10|50_20_20_10|adaptive)$" research/v52_scaleout_results.md
  grep -qE "^best_policy_mean_r: -?[0-9.]+$" research/v52_scaleout_results.md
  grep -qE "^adaptive_mean_r: -?[0-9.]+$" research/v52_scaleout_results.md
  grep -qE "^baseline_flat_1r_mean_r: -?[0-9.]+$" research/v52_scaleout_results.md
  test -s research/v52_scaleout_results.json
  python -c "import json,sys; d=json.load(open('research/v52_scaleout_results.json')); sys.exit(0 if len(d)>100 else 'too few trades replayed')"
  ```

### T6 -- Build the next homework deck: entries only, plus blind engine fires

- model: deepseek
- depends-on: T1

Two HTML decks in `research/`, same localStorage marking machinery the 5.2 decks use (copy
it, do not rewrite it), each exporting a jsonl on a Download button.

1. `research/omen-5.2-entry-deck.html` - **200 cards**, one per trading day not already
   marked in `research/marks/`. Each card asks for **entry bar and stop only, no exit**.
   Austin is spending about ten seconds a card, so the card must open on the chart with the
   marking controls already visible - no scrolling to find them.
2. `research/omen-5.2-blind-deck.html` - **100 cards**, each showing bars **up to and
   including the engine's fire bar and no further**, with the engine's grade **hidden**.
   The only question is take or skip, plus side. This measures engine precision against him
   and it is worthless if the grade leaks into the DOM - keep the answer out of the HTML
   entirely, in a separate `research/omen-5.2-blind-key.json`.

**Austin marks these on a Mac or a phone, not on the Windows box.** Each deck must be a
single self-contained HTML file - every bit of CSS and JS inline, all bar data embedded as
JSON in a `<script>` tag, zero external `src=`/`href=` to any host, zero `fetch()`/`XHR`.
No CDN charting library: draw the candles with inline canvas or SVG. A deck that loads
anything over the network is unusable where he actually is.

Both decks must survive a reload with marks intact. The 5.1 decks silently dropped every
mark to a save-handler closure bug that wrote all 60 cards to one id - test explicitly that
two different cards produce two different rows.

- **done-when:** both decks exist, the entry deck holds 200 cards excluding already-marked
  days, the blind deck holds 100 with no grade anywhere in the HTML, and the answer key is a
  separate file.
- **verify:**
  ```bash
  test -s research/omen-5.2-entry-deck.html
  test -s research/omen-5.2-blind-deck.html
  test -s research/omen-5.2-blind-key.json
  python -c "import re,sys; h=open('research/omen-5.2-entry-deck.html',encoding='utf-8').read(); n=len(re.findall(r'data-card-id=', h)); sys.exit(0 if n==200 else 'entry deck cards: %d' % n)"
  python -c "import re,sys; h=open('research/omen-5.2-blind-deck.html',encoding='utf-8').read(); n=len(re.findall(r'data-card-id=', h)); sys.exit(0 if n==100 else 'blind deck cards: %d' % n)"
  python -c "import re,sys; h=open('research/omen-5.2-blind-deck.html',encoding='utf-8').read(); sys.exit('grade leaked into blind deck' if re.search(r'(data-grade|\"grade\"\s*:)', h) else 0)"
  python -c "import re,sys,sys as s2; [s2.exit('external ref in %s' % f) for f in ['research/omen-5.2-entry-deck.html','research/omen-5.2-blind-deck.html'] if re.search(r'(src|href)\s*=\s*[\"\']https?://|fetch\s*\(|XMLHttpRequest', open(f,encoding='utf-8').read())]"
  ```

### T7 -- The verdict, and it is allowed to say no

- model: opus
- depends-on: everything

Read `research/v52_scaleout_results.md`, `research/v52_engine_scorecard.md`,
`research/exit_lab_calibration.md` and `research/trend_gate_agreement.md`. Write
`research/v52_verdict.md`.

Answer four questions, each in a few sentences, each pointing at a number:

1. **Does scaling out beat a flat exit?** Compare `best_policy_mean_r` to
   `baseline_flat_1r_mean_r` on corpus B, with a confidence interval. If the difference is
   inside the noise, say so plainly.
2. **Is 2:1 average over a year reachable from here?** State the gap between the best policy
   and 2.0R, and what would have to change to close it - entry quality, exit policy, or the
   trade rate.
3. **Does the engine see what Austin sees?** Use the scorecard. If `median_bar_offset` is
   consistently positive the engine is late and that is a separate, cheaper fix than
   regrading.
4. **What arms in 5.3?** Exactly one recommendation, and name the row that would do it.

Two standing traps, and the verdict must address both explicitly:

- **Tranche-1 marks are hindsight.** Austin marked these knowing how the day resolved. An
  87% win rate on his marks is not a live win rate, and corpus A is calibration, not
  evidence. Any claim of edge must rest on corpus B.
- **If `hod_rule_within_5_bars` is below 0.5**, the causal-HOD rule does not reproduce what
  his eye did, and every corpus-A number is measuring a different strategy. Say that at the
  top of the file rather than burying it.

The verdict must contain the exact line:

```
scaleout_verdict: <BEATS_FLAT|NO_DIFFERENCE|WORSE>
```

- **done-when:** `research/v52_verdict.md` answers all four questions from the real numbers
  and carries the verdict line.
- **verify:**
  ```bash
  grep -qE "^scaleout_verdict: (BEATS_FLAT|NO_DIFFERENCE|WORSE)$" research/v52_verdict.md
  python -c "import sys; t=open('research/v52_verdict.md',encoding='utf-8').read(); sys.exit(0 if all(k in t for k in ('hindsight','2.0R','median_bar_offset','5.3')) else 'verdict missing a required question')"
  ```

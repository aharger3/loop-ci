# OMEN 3.7 - make the engine see the trades Austin takes

status: ready
version: omen-3.7
repo: aharger3/tradingbot
doc: Projects/OMEN-CONSOLIDATED.md

target: find out why the engine emits no signal at three quarters of the bars Austin grades S,
fix the single biggest cause, and re-measure recall. This version is a detection version. It is
not a grading version and it is not a backtest version.

**Read this framing once; no row re-derives it.**

3.6 merged 2026-08-07 and answered the question it was built to answer, in `research/v36_verdict.md`:

- The engine **fires on 4 of 77 bars Austin grades S — 5%**. Counting every signal it produces at
  any grade including D-skips, still only **19/77 = 25%**. It emits nothing at all at ~75% of
  them. (`research/engine_recall.md`.)
- On the marked days it produces 516 raw signals: 442 graded D, 58 fired.
- **No feature separates S from A or S from X.** Sixteen features, two contrasts, every
  BH-FDR-adjusted p on S-vs-X is ~1.0; the minimum detectable effect was 45pp. The registered
  `S_GATE` (`displacement >= 0.888`) has a keep-rate gap of +12.5pp with a CI of [-20.7, +45.5].
  It ships **OFF** in `signal_runner.py` and this version does not touch it, re-tune it, or
  re-test it. (`research/s_gate_spec.md`.)
- **A filter cannot recover a setup that was never detected.** Every gate-shaped idea is premature
  until recall moves. Do not propose one.

So the whole version reduces to: *why is the engine silent, and what one change makes it speak?*

Facts each row would otherwise have to rediscover:

- **`entry_i` is minutes since 09:30**, and indexes directly into the day's RTH 1-minute bars.
- Marks live at **`research/austin_marks_v2.jsonl`** — 159 lines, `{"symbol","day","entry_i","tier"}`,
  tier in `S`/`A`/`X`, counts **77 S / 60 A / 22 X**, across 151 distinct `(symbol, day)` pairs.
- **54 of those 159 marks have no price data** (`research/bar_coverage.md`, 49 distinct
  symbol-days, all `no_archive_file`). 3.6's T2 was told to Polygon-backfill them and silently did
  not. So every 3.6 statistic rests on **48 S marks, not 77**. T1 below fixes this and everything
  downstream depends on it.
- Reuse, do not rewrite: **`research/t4_engine_recall.py`** is the working bar-by-bar replay
  harness (it reconstructs PDH/PDL from the prior archived day, PMH/PML from that day's
  04:00-09:29 bars, HTF bias from prior closes vs SMA20). **`research/mark_features.py`** is the
  working feature-vector builder. **`build_review_artifact.py`** is the working self-contained
  chart-artifact renderer.
- Module locations, because they are not where you would guess: `predicates.py`,
  `signal_runner.py`, `omen_bot.py`, `backtest_12mo.py`, `backtester.py`, `archive_1m.py` and
  `polygon_feed.py` are at the **repo root**. `levels.py` is under **`research/`**. Bars live at
  **`data_archive/<SYMBOL>/<YYYY-MM-DD>.csv`**.
- `POLYGON_API_KEY` is in the environment. **Never yfinance** — settled-dead on this project.
- Set `PYTHONIOENCODING=utf-8` before every Python run; the runner's console is cp1252 and a
  Unicode print kills a row silently.
- Baseline, do not recompute: **38.0% WR, +0.146R over 1,289 trades**
  (`backtest_metrics_full.json`). Breakeven at 2R is 33.333%.
- `omen-corpus-1.0` is VOID but **its data landed on `main` via PR #8 and is not to be rebuilt**:
  `research/corpus_instances.jsonl` (10,379 Discord-alert instances, 3,655 symbol-days,
  2024-04-02 .. 2026-07-03), `research/corpus_bar_coverage.md` (**3,595 covered symbol-days**),
  `research/corpus_engine_entries.jsonl` (the engine's fired entries over them, produced through
  `backtest_week.simulate_day`), and **13,815 1-minute CSVs** under `data_archive/`.

**Two answers Austin gave on 2026-08-07. They are settled inputs — no row re-elicits or
re-derives them, and no row contradicts them.**

**A. The One Candle Rule, defined at last.** In his words: *"you mark the downclose candle in an
uptrend and price respects it, or vice versa."* That is the order block — the last opposing-close
candle before the leg, whose zone price must respect. So `detect_order_block_setup` in
`omen_bot.py` **is** the One Candle Rule implementation and is not wrong. What is wrong is the
routing: `SignalType.ONE_CANDLE_RULE` is also used for **fair-value-gap** entries and **flag**
breakouts (`signal_runner.py:666, 687, 853, 872`), so three unrelated setups share one label and
none of them has a truthful per-setup win rate. `Trading-Bot-Rulesets.md:68` still reads
"[TO BE DOCUMENTED]" and must be filled in with the sentence above.

**B. Clustered levels are NOT a no-trade condition.** In his words: *"you can be in between
levels, what you're looking for is that clean price action break and retest of 1 level, but it
certainly helps if they are spread out more."* So the requirement is **one** level broken and
retested cleanly; being between levels is fine, and level spread is a probability input, not a
gate. This directly contradicts `_is_consolidation` (`signal_runner.py:457`), which returns `[]`
and abandons the entire bar — logging nothing — whenever PDH, PDL, OR-high and OR-low all sit
within 0.5% of their mean. **Treat that blanket kill as wrong on Austin's own authority.** T2
still measures how much damage it does; T5 does not need to relitigate whether it should go.

## Tasks

### [x] T1 -- Backfill the 49 missing symbol-days

- model: glm

`research/bar_coverage.md` lists every mark with `drop_reason = no_archive_file` — **49 distinct
pairs covering 54 marks** as of 3.6.

**Recompute that list against disk before fetching anything.** PR #8 (omen-corpus-1.0, merged
2026-08-07) banked **13,815 1-minute CSVs** into `data_archive/`, so some of those 49 pairs are
almost certainly already covered and `research/bar_coverage.md` is stale by exactly that much.
Derive the real missing set as `research/austin_marks_v2.jsonl` minus what exists on disk, and report
both numbers: how many of the 49 the corpus backfill already resolved, and how many you actually
had to fetch.

Fetch each with `polygon_feed.fetch_day(symbol, day_iso)`. It writes into the same `data_archive/`
layout and a repeat call is a disk read at zero API cost, so this is safe to re-run. Polygon
serves these dates — 3.6 confirmed IWM 2024-04-03 returns 716 1-minute bars.

`IWM` appears in the marks but is **absent from `archive_1m.py`'s `SYMBOLS` list**, which is why
none of its days were ever banked. Add `IWM` to that list. Check every marked symbol against the
list and add any other missing one the same way — `archive_1m.py` says to keep it in sync with
`live_scanner.DEFAULT_SYMBOLS`, so update both.

Write `research/bar_coverage_v2.md`: covered count out of 159 marks and out of 151 symbol-days in
the first ten lines, then a table of every pair still missing with the literal error Polygon
returned for it. A silent gap quietly shrinks every n in this version, which is exactly how 3.6
ended up reporting on 48 S marks while claiming 77.

- **done-when:** `research/bar_coverage_v2.md` exists, states a covered-out-of-159 count within its first 10 lines, lists every still-missing pair with the reason Polygon gave, and `grep -n IWM archive_1m.py` shows IWM in the SYMBOLS list.

### [x] T2 -- Autopsy every miss: why did no signal come out?

- model: glm
- depends-on: T1

**This is the row the version exists for.** Everything else is scaffolding around its answer.

For every mark in `research/austin_marks_v2.jsonl` that now has bars, replay the day bar-by-bar
through `SignalRunner.detect_signals` exactly as `research/t4_engine_recall.py` already does —
reuse that harness, do not write a second replay. At the mark's own `entry_i` (and within +/-2
bars of it), classify **why the engine did not fire there** into exactly one reason from this
fixed vocabulary. The vocabulary is fixed so the counts are comparable; do not invent extra
labels, but do record a free-text `detail` field alongside.

Reasons, in the order they can occur inside `detect_signals`:

- `detected` — an entry fired within +/-2 bars. Not a miss.
- `too_few_candles` — `len(self.candles) < 5` at that bar.
- `consolidation_early_return` — `self._is_consolidation(or_high, or_low, pdh, pdl)` returned True
  (`signal_runner.py:457`, all four key levels within 0.5% of their mean), so `detect_signals`
  returned `[]` and **nothing was ever logged**. This one is invisible in every existing log and
  is a prime suspect.
- `no_reference_level` — no level in `level_pairs` sits within 0.5% of the bar's close.
  `level_pairs` is OR high/low always, PDH/PDL and PMH/PML when reconstructable, and the
  `HODLOD_PAIR` only when `len(self.candles) >= 43` and the extreme is >= 30 bars old and not a
  near-duplicate of an existing level. Record which levels *were* available and the distance from
  close to the nearest one.
- `no_break_retest` — `detect_break_retest` returned falsy for every level in `level_pairs`.
  Record how far it got: was the level ever broken earlier in the session at all?
- `no_order_block` — `detect_order_block_setup` returned `None`. It has four distinct refusals and
  its own note string says which: no valid block / structure broken, `not isolated`, `no
  displacement`, `not retesting`. Record the exact one.
- `not_armed_84` — the mark is an 84% re-entry and the replay has no stopped-out prior trade in
  session state, so the branch could not arm. 3.6's harness has this limitation; record it rather
  than pretending it is a detection failure.
- `vetoed_htf` — a signal was built and `PriceActionAnalyzer.grade_trade` returned D because
  `htf_bias` opposed the direction (`omen_bot.py:141-144`).
- `vetoed_candle_colour` — `_grade_pa` returned D on `not candle.is_bullish` (long) or
  `not candle.is_bearish` (short) (`omen_bot.py:162` / `:175`).
- `vetoed_stop_too_tight` — the B&R path's `stock_risk < max(0.10, 0.0015 * close)`, or the order
  block path's `stock_risk < 0.50`, or `_route` dropped a C via `_min_viable_stop`
  (`signal_runner.py:302`).
- `vetoed_stop_too_wide` — the order block path's `stock_risk / close > 0.004`.
- `vetoed_pa_grade_D` — `_grade_pa` fell through to D for any other reason (price never retested
  the level on that bar).
- `fired_wrong_bar` — the engine fired on that symbol-day but more than 2 bars away from the mark.

Write `research/miss_autopsy.jsonl`, one line per mark with bars: the identity triple, the tier,
`miss_reason` from the vocabulary above, and a `detail` string. Then write
`research/miss_autopsy.md` leading with a **reason x tier** count table (rows = reason, columns =
S / A / X, plus a total column), sorted by the S column descending, so the single biggest cause of
S-blindness is the first data row on the page.

Below the table, for the top three reasons by S count, write a short paragraph naming what in the
code would have to change to convert those misses into signals, and roughly how many S marks it
would reach. Do **not** change any code in this row.

- **done-when:** `research/miss_autopsy.jsonl` has one line per mark that has bars, each carrying symbol/day/entry_i/tier/miss_reason with miss_reason drawn only from the fixed vocabulary above, and `research/miss_autopsy.md` opens with a reason-by-tier count table whose S column sums to the number of S marks with bars.

### [x] T2.1 -- Same autopsy over the 10,379-instance corpus

- model: glm
- depends-on: T2

`omen-corpus-1.0` was voided with its T4 unrun, and this row is where that question gets answered.
Its data is already on `main` and **must not be rebuilt**: `research/corpus_instances.jsonl`
(10,379 Discord-alert instances over 3,655 symbol-days), `research/corpus_bar_coverage.md`
(**3,595 covered symbol-days** — the denominator), and `research/corpus_engine_entries.jsonl` (the
engine's fired entries over those days, produced through `backtest_week.simulate_day`, which is
the same detection path `backtest_12mo.py` uses).

Reuse **the classifier T2 wrote** — import it, do not write a second one. Two classifiers means
two vocabularies and the counts stop being comparable, which is the whole point of running this
against T2's marks.

For every corpus instance that has bars and resolves to a bar index, classify why the engine
produced no entry there, using T2's identical reason vocabulary. Note the one structural
difference and state it in the report: corpus instances are **alerts from Discord**, not Austin's
own graded setups, so there is no S/A/X tier — report reasons as a flat distribution plus a split
by `channel` (`scarface-alerts` 4,020, `jdub-alerts` 3,080, remainder per
`research/corpus_instances.md`).

Write `research/corpus_miss_autopsy.jsonl` (one line per classified instance) and
`research/corpus_miss_autopsy.md` leading with the reason-count table over the whole corpus, then
the same table split by channel.

Then, and this is the payoff: put the corpus reason distribution **side by side with T2's S-mark
reason distribution** in a single table. If the same reason tops both at n=3,595 and at n≈77, that
is the strongest evidence this project has for what to change. If they disagree, say so plainly —
it would mean Austin's setups fail differently from the alerts, and T5 must follow the S column.

- **done-when:** `research/corpus_miss_autopsy.md` exists, states the number of corpus instances classified out of the 3,595 covered symbol-days, carries a reason-count table using the same vocabulary as `research/miss_autopsy.md`, and contains a side-by-side table comparing the corpus reason distribution against the S-mark reason distribution.

### T3 -- Rule 7 and rule 10 as numbers

- model: glm
- depends-on: T1

Austin's two hardest rejections, and the engine represents neither. Encode both as measurable
features and see whether they separate his tiers, since nothing in 3.6's 16-feature vector did.

**Rule 7 — speed of the retest.** From his dictation: "ideally the break and retest happens as
soon as possible. If it happens over 3, 4, 5, 6, or 7 candles it's decent. If it takes too many
candles probability decreases." Feature: **bars elapsed between the break candle and the retest
candle**. The break is the last bar before `entry_i` whose *body* closed beyond the reference
level; the retest is the bar whose wick returns to that level. Emit `null` where no break is
identifiable, and count how often that happens — a high null rate is itself the finding.

**Rule 10 — left-side pivot noise.** From his X card: "a bunch of candles or pivot structures
already there before your break... if the break and retest is not clean or the order block is not
clean." Feature: **the count of swing pivots in the 20 bars before the reference level was
broken**, using the same 3-bar swing definition `MarketStructure.update` uses in `omen_bot.py`
(a high above both neighbours, a low below both). Also emit **how many of those pivots sit within
0.2% of the reference level itself** — that is the "noise at the level" version of it, and is
closer to what he describes than a raw count.

Compute both at every mark that has bars, reusing `research/mark_features.py`'s loading and
leakage discipline. **Leakage rule, and it voids the row if broken: no feature may read any bar at
index > `entry_i`.** State in the report how you enforced it, not that you intended to.

Then report, for each of the two features, the S-vs-X and S-vs-A separation: Cohen's d, a 95% CI
from a block bootstrap over whole trading days with 10,000 resamples, and the minimum detectable
effect at the n you actually have. 3.6's arms were n=48/45/12 and detected nothing at 45pp; if
these arms are similar, say the result is underpowered and report the MDE rather than calling it a
null.

Write `research/rule7_rule10.jsonl` (identity triple, tier, both features) and
`research/rule7_rule10.md` (the null rate for rule 7, and the two separation tables).

- **done-when:** `research/rule7_rule10.jsonl` has one line per mark with bars carrying `bars_break_to_retest` and `left_pivot_count` keys, and `research/rule7_rule10.md` reports d, a bootstrap CI, and an MDE for each feature on both the S-vs-X and S-vs-A contrasts.

### [x] T4 -- The tradable universe, by options volume

- model: deepseek

Austin trades names with roughly **200,000+ daily options contracts** and wants a top-10 focus
list out of it. The scanner currently runs a hand-picked 28 in `archive_1m.py`'s `SYMBOLS` /
`live_scanner.DEFAULT_SYMBOLS` with no liquidity rule behind it at all.

Try Polygon first: for each symbol in `SYMBOLS`, sum recent daily options contract volume across
its option chain (`/v3/reference/options/contracts` to enumerate, `/v2/aggs` per contract, or the
options snapshot endpoint — whichever the key's plan actually serves). **The plan may not include
options data.** If it returns 401/403/NOT_AUTHORIZED, do not retry it in a loop and do not fake a
number: record the exact endpoint and HTTP status, then fall back to ranking by **median daily
dollar volume** computed from the 1-minute bars already in `data_archive/` (sum of
`close * volume` per RTH day, median over the last 60 archived days) and label the column plainly
as a proxy.

Write `research/universe.md`: one row per symbol with the volume figure and its source
(`polygon_options` or `dollar_volume_proxy`), sorted descending, the **top 10 flagged**, and an
explicit statement of which source was used and why. If the proxy was used, say in one line that
the 200k options threshold was **not** applied because the data was unavailable — do not silently
substitute a different threshold.

This row changes no code. `SYMBOLS` stays as it is until Austin picks from the ranked list.

- **done-when:** `research/universe.md` exists, has one row per symbol in `archive_1m.py`'s SYMBOLS list with a volume figure and a source label, flags exactly 10 as the focus list, and names either the Polygon endpoint used or the exact HTTP status that forced the proxy.

### [x] T5 -- Widen detection at the top miss reason, and rename D to X

- model: opus
- depends-on: T2

Read `research/miss_autopsy.md` and `research/miss_autopsy.jsonl`. **Do not recompute the
autopsy.** The top row of the S column names the single biggest cause of S-blindness; this row
fixes that one cause and nothing else.

Also read `research/corpus_miss_autopsy.md` **if it exists** — T2.1 runs alongside this row and
may not have finished. It is corroboration only: where it agrees with the S table, note that in
`research/detect_wide.md`; where it disagrees, or where it is absent, **follow the S column
regardless**. Austin's own graded setups are the target; the Discord alerts are not. Never block
or fail because that file is missing.

Three changes, all in one row because all three touch `signal_runner.py` and parallel edits would
conflict.

**Change 1 — the widening.** Implement the minimum change that converts the top miss reason into
detected signals, following the repo's existing A/B-able flag pattern (`BNR_DISPLACEMENT_GATE`,
`HTF_BIAS_GATE`, `S_GATE`: a module global in `signal_runner.py`, **default OFF**, flipped at
runtime by the harness). Name it `DETECT_WIDE` and default it to `False`, so shipped behaviour is
byte-identical to today. Its docstring names `research/miss_autopsy.md` as its source and states
which miss reason it targets and the S-mark count that reason carried.

Judgement is yours and this is why the row is opus, but the change must be *narrow* — one
mechanism, not a rewrite. Some likely shapes, depending on what T2 found:

- if `consolidation_early_return` tops the table, **Austin has already ruled on it** (framing
  section B): being between clustered levels is fine, what he needs is one level broken and
  retested cleanly, and level spread is a probability input rather than a gate. So the blanket
  `return []` in `_is_consolidation` (`signal_runner.py:457`) goes — do not relitigate whether it
  should. Replace it with a recorded flag on the signal (level spread as a number) and make the
  path *log* what it used to silently discard.
- if `no_reference_level` tops it, the fix is the level vocabulary: `HODLOD_PAIR`'s >= 43-bar and
  >= 30-bar-age conditions, or the absence of swing-pivot and round-number levels entirely.
- if `no_break_retest` tops it, the fix is `detect_break_retest`'s geometry — its window, or its
  requirement that the break close beyond the level by body.

Write `research/detect_wide.md` first, before editing: which reason you are targeting, its S
count, the exact mechanism you are changing, and **your prediction for the recall number T6 will
produce**. Registering the prediction before the measurement is the point.

**Change 2 — the rename.** `D` and `X` both mean *skip*, so this is a pure rename with no
semantic risk. In `omen_bot.py`'s `TradeGrade`, add `X` as the skip grade and keep `D` as an alias
so nothing that reads the old letter breaks; update `signal_runner.py`'s `_route` and
`_GRADE_RANK` accordingly. Also add an `austin_tier` field to the signal dict and the log record,
**always emitted as `None`** for now. It is a slot for a future S/A/C mapping, not a mapping.

**Do not** map `A+`/`A`/`B`/`C` onto `S`/`A`/`C`. There is no evidence for that mapping: `B` is
the only profitable engine tier (+$62,451 at 36.6% over 693 trades in `backtest_report_12mo.md`)
while `A+` and `A` both lose money at ~31%, and 3.6 showed no feature currently tells S from A.
Inventing the mapping today would encode a falsehood in the taxonomy.

**Change 3 — stop three setups sharing one label.** Austin defined the One Candle Rule on
2026-08-07 (framing section A): *"you mark the downclose candle in an uptrend and price respects
it, or vice versa"* — which is the order block, so `detect_order_block_setup` is the correct
implementation of it and stays as it is. The defect is that `SignalType.ONE_CANDLE_RULE` is *also*
emitted for **fair-value-gap** entries and **flag** breakouts (`signal_runner.py:666, 687, 853,
872`), so no per-setup win rate for any of the three is truthful. Add `SignalType.FAIR_VALUE_GAP`
and `SignalType.FLAG` in `omen_bot.py` and route those two branches to them, leaving
`ONE_CANDLE_RULE` for the order block alone. `FLAG_ENABLED` is already `False`
(`signal_runner.py:66`), so the flag branch is dormant and this is a label fix, not a behaviour
change. Then replace the "[TO BE DOCUMENTED]" body of Setup 3 in `Trading-Bot-Rulesets.md:68`
with Austin's sentence above.

Write `test_detect_wide.py` at the repo root: plain asserts, no pytest. At least one case the
widened path accepts and one it still rejects, plus an assertion that `DETECT_WIDE` defaults to
`False`, plus an assertion that a skip grade serialises as `X`, plus an assertion that
`SignalType.FAIR_VALUE_GAP` and `SignalType.ONE_CANDLE_RULE` are distinct values.

- **done-when:** `python test_detect_wide.py` exits 0, `grep -n "DETECT_WIDE" signal_runner.py` shows the module global defaulting to False, `research/detect_wide.md` states the targeted miss reason and a predicted recall number, `grep -n "austin_tier" signal_runner.py` finds the field, and `grep -n "FAIR_VALUE_GAP" omen_bot.py signal_runner.py` shows the new SignalType in both files.

### T6 -- Re-measure recall, widening OFF vs ON

- model: glm
- depends-on: T5

The number 3.7 lives or dies on.

Run `research/t4_engine_recall.py` **twice** over the marks in `research/austin_marks_v2.jsonl`,
against the archive as it stands after T1's backfill: once with `DETECT_WIDE` OFF (the shipped
default — this is the baseline arm) and once ON, flipping the module global at runtime the same
way `research/c1_analyze.py` flips `BNR_DISPLACEMENT_GATE`.

Save `research/recall_off.md` and `research/recall_on.md`, then write `research/recall_ab.md`
containing:

- a **mechanism check first** — the raw signal count and fired count for both arms. If the two
  arms are identical, the flag never took effect and everything below it is void; say exactly that
  instead of reporting a null.
- fired S/A/X recall for both arms, and any-signal-any-grade S/A/X recall for both arms, as counts
  over the same denominators. The OFF arm must be compared against 3.6's numbers (fired S 4/77,
  any-signal S 19/77) and any difference explained — after T1's backfill more marks are testable,
  so the denominators legitimately change and the report must say so rather than quietly
  reporting a bigger number as an improvement.
- precision for both arms: engine entries on marked days, how many land within +/-2 bars of a
  mark, and the tier mix of those that do. **A widening that raises recall by firing everywhere is
  not a win** — if precision collapses, say so plainly in the same paragraph as the recall gain.
- signals per symbol per day for both arms, so the trade-count cost of the widening is a number
  on the page.

Do not run `backtest_12mo.py` in this row. P&L is not this version's question and a 90-minute
backtest is what cancelled the 3.6 run.

- **done-when:** `research/recall_ab.md` exists, its first 15 lines carry the mechanism check with raw and fired signal counts for both arms, and it states fired S recall and any-signal S recall for OFF and ON over stated denominators plus precision for both arms.

### [x] T7 -- Render the next marking batch

- model: deepseek
- depends-on: T2

Austin's labelled corpus is 159 marks and every effect measured on it so far has been
underpowered. Growing it is the highest-value thing he personally can do, so this row makes the
next batch ready to grade without him having to set anything up.

Read `research/miss_autopsy.jsonl`. Build a batch of **60 charts**, drawn as:

- every S mark whose `miss_reason` is not `detected` (the engine is blind here; his grade on the
  same bar is the label that teaches it), up to 40 of them, most recent first;
- filled to 60 with engine entries on marked days that Austin did **not** mark — read these from
  `research/engine_entries.jsonl`, which 3.6 wrote. These are the false positives; his X on them
  is worth as much as his S.

Follow `build_review_artifact.py`'s existing pattern exactly — it already emits a self-contained
`review_artifact.html` with the entry candle unmistakable and levels coloured by type
(premarket / prior-day / opening-range), which are Austin's stated asks. Reuse its template and
its level-colouring; change only the data source. Bars come from
`data_archive/<SYMBOL>/<DAY>.csv`, windowed to roughly 40 bars before and 30 after `entry_i`, with
the entry bar marked.

Each card carries symbol, date, time-of-day from `entry_i`, and — for the S misses — the
`miss_reason` printed on the card, so grading doubles as a check on T2's autopsy. **Do not print
Austin's existing tier on the card**; these are graded blind or they are worthless as labels.

Emit `research/mark_batch_02.html` and `research/mark_batch_02.md` (what is in the batch, the
split between S-misses and unmarked engine entries, and the one-line instruction for how to
return grades).

- **done-when:** `research/mark_batch_02.html` exists, is self-contained with no external script or stylesheet references, embeds exactly 60 chart cards, and `research/mark_batch_02.md` states the S-miss / unmarked-engine-entry split summing to 60.

### T8 -- Verdict

- model: opus
- depends-on: everything

Read `research/bar_coverage_v2.md`, `research/miss_autopsy.md`, `research/corpus_miss_autopsy.md`,
`research/rule7_rule10.md`, `research/universe.md`, `research/detect_wide.md`,
`research/recall_ab.md`, `research/mark_batch_02.md`. **Do not recompute any number and do not run
any backtest.**

Answer, in order:

1. **Why is the engine blind?** Name the top three miss reasons with their S counts, out of the S
   marks that had bars. If one reason carries the majority, say so plainly. Then say whether the
   10,379-instance corpus agrees: same top reason at n=3,595 symbol-days is corroboration worth
   stating; a disagreement means Austin's setups fail differently from the Discord alerts, and
   that is itself a finding.
2. **Did the widening work?** OFF vs ON fired S recall and any-signal S recall, over stated
   denominators, and what it cost in precision and in signals per symbol per day. If T6's
   mechanism check shows the flag did not take effect, that is the answer and nothing else in T6
   is admissible. Compare against the prediction registered in `research/detect_wide.md` and say
   whether it held.
3. **Do rule 7 or rule 10 do anything?** Effect, CI, and MDE for each. At these sample sizes,
   distinguish "no effect" from "could not have seen one" — 3.6's MDE was 45pp and this version's
   arms are not much larger.
4. **What is the sample situation?** Marks with bars after T1's backfill, out of 159, and what
   `research/mark_batch_02.md` adds if Austin grades it.
5. **The one change to make next** — one concrete thing, or state plainly that nothing testable is
   left without more labels and name exactly what data would be needed.

Explicitly do **not** recommend a new gate, filter, or score unless fired S recall in
`research/recall_ab.md` is above 40%. Below that the engine still is not seeing the trades and a
filter has nothing to filter; say that instead.

Write `research/v37_verdict.md`, ending with a `FOR AUSTIN` section of ten lines or fewer, written
for someone who trades this tomorrow and will not open any other file.

- **done-when:** `research/v37_verdict.md` exists, answers all five numbered questions in order, and ends with a `FOR AUSTIN` section of ten lines or fewer.




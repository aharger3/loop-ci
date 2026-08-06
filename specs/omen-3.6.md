# OMEN 3.6 - turn the 78 S trades into a gate the engine actually runs

status: ready
version: omen-3.6
repo: aharger3/tradingbot
doc: Projects/omen-trading.md

target: fit a signal gate from Austin's own S/A/X verdicts, ship it into signal_runner.py as a
real flag, and A/B it on the 12-month backtest - so the answer is a new backtest number, not
another report.

**This version must end in changed engine code and a before/after backtest.** Every prior OMEN
version produced analysis and stopped. Austin: *"I want my S trades to change the code so we can
run backtests and see new results and if we're getting closer to having an edge."* A row that
writes only markdown has not done its job.

Framing, so no row re-derives it:

- Austin hand-graded 162 entries `s`/`a`/`x` (78/60/24, 159 unique triples). 3.5 tried to apply
  them as a re-grade of `research/blind_marks_all.jsonl` and matched **0 of 162** - the two sets
  share zero `(symbol, day)` pairs, so they are a second independent marking session, not a
  re-grade. That premise is dead; do not retry it, and do not merge these into any corpus file.
- **`entry_i` is minutes since 09:30.** Verified against all 117 `entry_t` values in the existing
  corpus, zero mismatches. So every verdict resolves to an exact 1-minute bar from
  `(symbol, day, entry_i)` with no chart manifest and no marking-tool export.
- **The marks are a genuinely held-out sample.** They were drawn from ~960 random symbol-days,
  NOT from the engine's 1,289 backtest trades. So a gate fit on the marks and then tested on the
  engine's trades is not fitting and scoring the same data. Say this in the verdict; it is the
  one thing that makes this version's number worth anything.
- Baseline to beat, do not recompute it: **38.0% WR, +0.146R over 1,289 trades**
  (`research/backtest_metrics_full.json`).
- `research/levels.py` already carries the HOD/LOD fix (`seg = bars[: entry_i]`, merged
  2026-08-06, `research/test_levels.py` passing). Do not re-apply it.

Module locations, because they are not where you would guess: `predicates.py`, `signal_runner.py`,
`backtest_12mo.py`, `backtester.py` and `polygon_feed.py` are at the **repo root**.
`levels.py` is under **`research/`**. Bars live in `data_archive/<SYMBOL>/<YYYY-MM-DD>.csv`.

Statistical floor, not renegotiable inside a row: **4 percentage points of win rate, or Cohen's
d = 0.15**. Block-bootstrap over whole trading days, 10,000 resamples, for every CI. BH-FDR at
q = 0.10. The X arm is n=24 - a row that finds nothing says "underpowered at n=24" and reports
the minimum detectable effect it actually had, rather than "no effect".

## Tasks

### T1 -- Normalize the 162 verdicts into a labels file

- model: glm

The verdicts are the JSON array below - 162 objects, each `{"symbol","day","entry_i","verdict"}`
with verdict in `s`/`a`/`x`. It is inline on purpose: rows share no memory and this array is the
only copy in either repo. Write it out verbatim to `research/austin_verdicts.json` first, before
transforming anything - later rows need it and you are the only row that can see it.

```json
[{"symbol":"HOOD","day":"2025-08-04","entry_i":40,"verdict":"a"},{"symbol":"SOFI","day":"2026-03-11","entry_i":63,"verdict":"a"},{"symbol":"QQQ","day":"2025-06-25","entry_i":48,"verdict":"a"},{"symbol":"SPY","day":"2026-01-08","entry_i":42,"verdict":"x"},{"symbol":"MSFT","day":"2026-02-11","entry_i":20,"verdict":"a"},{"symbol":"QQQ","day":"2025-02-26","entry_i":28,"verdict":"s"},{"symbol":"SPY","day":"2026-02-09","entry_i":24,"verdict":"a"},{"symbol":"HOOD","day":"2026-05-19","entry_i":19,"verdict":"a"},{"symbol":"META","day":"2025-09-23","entry_i":9,"verdict":"a"},{"symbol":"NVDA","day":"2024-11-19","entry_i":18,"verdict":"a"},{"symbol":"COIN","day":"2025-10-21","entry_i":8,"verdict":"s"},{"symbol":"IWM","day":"2026-07-24","entry_i":29,"verdict":"s"},{"symbol":"QQQ","day":"2025-06-24","entry_i":15,"verdict":"s"},{"symbol":"META","day":"2026-06-10","entry_i":18,"verdict":"x"},{"symbol":"SPY","day":"2024-10-22","entry_i":41,"verdict":"a"},{"symbol":"MARA","day":"2025-08-18","entry_i":23,"verdict":"x"},{"symbol":"IWM","day":"2024-04-03","entry_i":13,"verdict":"s"},{"symbol":"IWM","day":"2024-04-03","entry_i":73,"verdict":"s"},{"symbol":"IWM","day":"2024-04-03","entry_i":73,"verdict":"s"},{"symbol":"AMZN","day":"2025-08-14","entry_i":18,"verdict":"x"},{"symbol":"CRM","day":"2025-07-02","entry_i":17,"verdict":"a"},{"symbol":"MARA","day":"2025-04-02","entry_i":14,"verdict":"a"},{"symbol":"BABA","day":"2025-07-22","entry_i":20,"verdict":"s"},{"symbol":"TSM","day":"2025-10-07","entry_i":74,"verdict":"a"},{"symbol":"QQQ","day":"2024-12-23","entry_i":47,"verdict":"a"},{"symbol":"CRM","day":"2026-05-07","entry_i":18,"verdict":"x"},{"symbol":"IWM","day":"2025-12-01","entry_i":11,"verdict":"s"},{"symbol":"SPY","day":"2026-03-25","entry_i":10,"verdict":"x"},{"symbol":"AMD","day":"2026-04-21","entry_i":35,"verdict":"a"},{"symbol":"GOOGL","day":"2025-08-07","entry_i":18,"verdict":"s"},{"symbol":"QQQ","day":"2024-05-08","entry_i":8,"verdict":"s"},{"symbol":"HOOD","day":"2025-03-04","entry_i":44,"verdict":"s"},{"symbol":"INTC","day":"2025-06-05","entry_i":10,"verdict":"x"},{"symbol":"QQQ","day":"2024-03-05","entry_i":11,"verdict":"a"},{"symbol":"QQQ","day":"2024-03-05","entry_i":21,"verdict":"s"},{"symbol":"QQQ","day":"2025-03-17","entry_i":16,"verdict":"s"},{"symbol":"SPY","day":"2024-04-03","entry_i":9,"verdict":"s"},{"symbol":"GOOG","day":"2025-06-10","entry_i":21,"verdict":"a"},{"symbol":"QQQ","day":"2026-02-11","entry_i":32,"verdict":"s"},{"symbol":"QQQ","day":"2026-02-11","entry_i":45,"verdict":"s"},{"symbol":"SPY","day":"2025-02-21","entry_i":18,"verdict":"x"},{"symbol":"IWM","day":"2025-09-05","entry_i":12,"verdict":"s"},{"symbol":"IWM","day":"2025-09-05","entry_i":51,"verdict":"a"},{"symbol":"QQQ","day":"2025-12-05","entry_i":27,"verdict":"s"},{"symbol":"QQQ","day":"2025-12-05","entry_i":35,"verdict":"s"},{"symbol":"CRM","day":"2025-06-02","entry_i":27,"verdict":"s"},{"symbol":"QQQ","day":"2025-03-18","entry_i":13,"verdict":"s"},{"symbol":"SPY","day":"2025-06-02","entry_i":40,"verdict":"a"},{"symbol":"QQQ","day":"2024-01-04","entry_i":41,"verdict":"s"},{"symbol":"MSFT","day":"2026-01-20","entry_i":12,"verdict":"s"},{"symbol":"IWM","day":"2024-02-28","entry_i":9,"verdict":"s"},{"symbol":"IWM","day":"2024-02-28","entry_i":18,"verdict":"a"},{"symbol":"AMZN","day":"2026-07-17","entry_i":7,"verdict":"a"},{"symbol":"COIN","day":"2026-03-04","entry_i":43,"verdict":"a"},{"symbol":"MU","day":"2025-11-07","entry_i":22,"verdict":"s"},{"symbol":"QQQ","day":"2025-01-16","entry_i":23,"verdict":"s"},{"symbol":"QQQ","day":"2025-12-30","entry_i":24,"verdict":"s"},{"symbol":"GOOG","day":"2025-12-08","entry_i":58,"verdict":"x"},{"symbol":"TSLA","day":"2026-02-18","entry_i":42,"verdict":"s"},{"symbol":"QQQ","day":"2024-10-03","entry_i":18,"verdict":"s"},{"symbol":"UBER","day":"2026-06-09","entry_i":11,"verdict":"a"},{"symbol":"NVDA","day":"2024-11-18","entry_i":10,"verdict":"s"},{"symbol":"QQQ","day":"2025-05-16","entry_i":63,"verdict":"a"},{"symbol":"IWM","day":"2025-04-10","entry_i":16,"verdict":"s"},{"symbol":"MARA","day":"2025-05-14","entry_i":23,"verdict":"x"},{"symbol":"GOOGL","day":"2024-09-03","entry_i":10,"verdict":"a"},{"symbol":"ORCL","day":"2025-11-03","entry_i":17,"verdict":"s"},{"symbol":"ORCL","day":"2025-03-28","entry_i":12,"verdict":"s"},{"symbol":"IWM","day":"2025-10-21","entry_i":9,"verdict":"s"},{"symbol":"HOOD","day":"2025-02-24","entry_i":16,"verdict":"a"},{"symbol":"QQQ","day":"2024-08-23","entry_i":36,"verdict":"s"},{"symbol":"UBER","day":"2025-09-11","entry_i":15,"verdict":"s"},{"symbol":"GOOGL","day":"2024-10-15","entry_i":32,"verdict":"s"},{"symbol":"NVDA","day":"2024-12-16","entry_i":12,"verdict":"a"},{"symbol":"MSFT","day":"2025-03-04","entry_i":13,"verdict":"s"},{"symbol":"QQQ","day":"2025-01-10","entry_i":13,"verdict":"s"},{"symbol":"TSLA","day":"2024-03-27","entry_i":13,"verdict":"s"},{"symbol":"QQQ","day":"2026-03-04","entry_i":42,"verdict":"s"},{"symbol":"MARA","day":"2026-07-09","entry_i":19,"verdict":"s"},{"symbol":"CRM","day":"2025-11-18","entry_i":16,"verdict":"a"},{"symbol":"NVDA","day":"2024-12-30","entry_i":34,"verdict":"a"},{"symbol":"MU","day":"2026-01-28","entry_i":13,"verdict":"s"},{"symbol":"SPY","day":"2025-09-25","entry_i":45,"verdict":"a"},{"symbol":"HOOD","day":"2026-04-13","entry_i":16,"verdict":"s"},{"symbol":"SPY","day":"2025-02-20","entry_i":35,"verdict":"a"},{"symbol":"TSM","day":"2026-05-29","entry_i":23,"verdict":"s"},{"symbol":"GOOG","day":"2026-02-23","entry_i":19,"verdict":"x"},{"symbol":"MARA","day":"2026-07-17","entry_i":13,"verdict":"a"},{"symbol":"SPY","day":"2024-02-22","entry_i":25,"verdict":"a"},{"symbol":"UBER","day":"2026-01-06","entry_i":22,"verdict":"a"},{"symbol":"SPY","day":"2025-11-05","entry_i":52,"verdict":"a"},{"symbol":"QQQ","day":"2024-02-01","entry_i":44,"verdict":"x"},{"symbol":"SPY","day":"2026-03-03","entry_i":17,"verdict":"s"},{"symbol":"IWM","day":"2024-03-22","entry_i":24,"verdict":"s"},{"symbol":"SPY","day":"2025-03-18","entry_i":13,"verdict":"s"},{"symbol":"PLTR","day":"2024-10-23","entry_i":21,"verdict":"s"},{"symbol":"QQQ","day":"2026-07-09","entry_i":11,"verdict":"s"},{"symbol":"ORCL","day":"2026-06-09","entry_i":8,"verdict":"a"},{"symbol":"SPY","day":"2026-05-05","entry_i":10,"verdict":"a"},{"symbol":"AMD","day":"2026-05-14","entry_i":25,"verdict":"a"},{"symbol":"HOOD","day":"2026-02-05","entry_i":40,"verdict":"s"},{"symbol":"TSLA","day":"2024-12-03","entry_i":8,"verdict":"a"},{"symbol":"IWM","day":"2024-08-22","entry_i":27,"verdict":"s"},{"symbol":"COIN","day":"2025-12-01","entry_i":11,"verdict":"a"},{"symbol":"QQQ","day":"2024-01-30","entry_i":35,"verdict":"x"},{"symbol":"ORCL","day":"2025-07-08","entry_i":7,"verdict":"s"},{"symbol":"TSLA","day":"2024-06-24","entry_i":9,"verdict":"s"},{"symbol":"UBER","day":"2026-07-06","entry_i":12,"verdict":"s"},{"symbol":"QQQ","day":"2026-03-06","entry_i":47,"verdict":"x"},{"symbol":"MARA","day":"2025-07-30","entry_i":30,"verdict":"a"},{"symbol":"MARA","day":"2024-09-09","entry_i":38,"verdict":"x"},{"symbol":"IWM","day":"2026-06-24","entry_i":28,"verdict":"a"},{"symbol":"MARA","day":"2024-10-18","entry_i":11,"verdict":"s"},{"symbol":"HOOD","day":"2026-07-07","entry_i":37,"verdict":"a"},{"symbol":"TSLA","day":"2024-02-05","entry_i":16,"verdict":"a"},{"symbol":"MU","day":"2025-12-08","entry_i":12,"verdict":"x"},{"symbol":"UBER","day":"2025-07-31","entry_i":48,"verdict":"a"},{"symbol":"PLTR","day":"2026-03-31","entry_i":23,"verdict":"s"},{"symbol":"IWM","day":"2026-05-28","entry_i":46,"verdict":"s"},{"symbol":"MARA","day":"2024-12-17","entry_i":49,"verdict":"s"},{"symbol":"SPY","day":"2025-12-02","entry_i":14,"verdict":"x"},{"symbol":"AMD","day":"2025-06-05","entry_i":6,"verdict":"s"},{"symbol":"IWM","day":"2024-08-01","entry_i":44,"verdict":"a"},{"symbol":"QQQ","day":"2024-03-15","entry_i":11,"verdict":"s"},{"symbol":"MSFT","day":"2026-06-10","entry_i":17,"verdict":"a"},{"symbol":"UBER","day":"2025-02-07","entry_i":22,"verdict":"s"},{"symbol":"CRM","day":"2025-09-26","entry_i":12,"verdict":"a"},{"symbol":"PLTR","day":"2025-09-18","entry_i":14,"verdict":"s"},{"symbol":"SOFI","day":"2024-10-30","entry_i":16,"verdict":"s"},{"symbol":"QQQ","day":"2025-01-28","entry_i":40,"verdict":"a"},{"symbol":"QQQ","day":"2024-12-16","entry_i":28,"verdict":"s"},{"symbol":"MARA","day":"2026-07-20","entry_i":11,"verdict":"a"},{"symbol":"SOFI","day":"2026-05-20","entry_i":55,"verdict":"a"},{"symbol":"NVDA","day":"2025-03-25","entry_i":25,"verdict":"a"},{"symbol":"COIN","day":"2025-06-26","entry_i":18,"verdict":"s"},{"symbol":"TSLA","day":"2024-01-12","entry_i":18,"verdict":"x"},{"symbol":"QQQ","day":"2025-05-07","entry_i":31,"verdict":"a"},{"symbol":"HOOD","day":"2025-12-29","entry_i":12,"verdict":"x"},{"symbol":"ORCL","day":"2025-09-17","entry_i":11,"verdict":"a"},{"symbol":"AMD","day":"2026-03-04","entry_i":9,"verdict":"a"},{"symbol":"AMZN","day":"2026-04-10","entry_i":74,"verdict":"a"},{"symbol":"UBER","day":"2025-08-13","entry_i":25,"verdict":"s"},{"symbol":"IWM","day":"2025-12-04","entry_i":56,"verdict":"s"},{"symbol":"IWM","day":"2024-09-24","entry_i":35,"verdict":"x"},{"symbol":"IWM","day":"2024-09-24","entry_i":53,"verdict":"x"},{"symbol":"HOOD","day":"2026-07-10","entry_i":23,"verdict":"s"},{"symbol":"SPY","day":"2025-07-01","entry_i":41,"verdict":"a"},{"symbol":"GOOG","day":"2025-04-04","entry_i":26,"verdict":"a"},{"symbol":"SPY","day":"2024-06-11","entry_i":23,"verdict":"s"},{"symbol":"SPY","day":"2026-03-02","entry_i":24,"verdict":"s"},{"symbol":"COIN","day":"2026-04-09","entry_i":30,"verdict":"s"},{"symbol":"SPY","day":"2026-03-05","entry_i":56,"verdict":"s"},{"symbol":"NVDA","day":"2026-05-21","entry_i":10,"verdict":"a"},{"symbol":"MSFT","day":"2025-03-20","entry_i":28,"verdict":"s"},{"symbol":"BABA","day":"2025-12-26","entry_i":36,"verdict":"a"},{"symbol":"QQQ","day":"2025-07-01","entry_i":72,"verdict":"x"},{"symbol":"QQQ","day":"2025-07-01","entry_i":72,"verdict":"x"},{"symbol":"QQQ","day":"2025-07-01","entry_i":72,"verdict":"x"},{"symbol":"SPY","day":"2025-11-19","entry_i":9,"verdict":"s"},{"symbol":"SPY","day":"2024-09-19","entry_i":19,"verdict":"s"},{"symbol":"QQQ","day":"2025-02-25","entry_i":16,"verdict":"s"},{"symbol":"QQQ","day":"2025-02-25","entry_i":53,"verdict":"a"}]
```

Write `research/austin_marks_v2.jsonl`, one object per line:
`{"symbol","day","entry_i","tier"}` with tier uppercased to S/A/X.

- Identity is `symbol|day|entry_i`. There are **3 duplicate triples** (159 unique of 162). Keep
  the LAST occurrence in file order; do not error.
- Assert `0 <= entry_i <= 390` on every row; fail loudly listing any row outside it.

Also write `research/austin_marks_v2.md`: the S/A/X counts, distinct `(symbol, day)` count, the
duplicates you collapsed, and the entry_i min/max.

- **done-when:** `research/austin_verdicts.json` holds 162 objects, `research/austin_marks_v2.jsonl` has exactly 159 lines each with symbol/day/entry_i/tier and tier in S/A/X, and `research/austin_marks_v2.md` states the three tier counts summing to 159.

### T2 -- Close the 1-minute bar gap for the marked days

- model: glm
- depends-on: T1

The marks cover 151 distinct `(symbol, day)` pairs. **102 already have bars** at
`data_archive/<SYMBOL>/<YYYY-MM-DD>.csv`; **49 do not.** `IWM` is in the marks but absent from
`archive_1m.py`'s `SYMBOLS` list, so none of its days are banked. Read the pairs from
`research/austin_marks_v2.jsonl`.

Fetch every missing pair with `polygon_feed.fetch_day()` - it caches into the same
`data_archive/` layout, so a repeat call is a disk read at zero API cost. `POLYGON_API_KEY` is
set in the environment. Confirmed working for the older dates: IWM 2024-04-03 returns 716
1-minute bars. **Never yfinance** - settled-dead on this project.

Add `IWM` to `archive_1m.py`'s `SYMBOLS` list while you are here, so the daily job banks it from
now on.

Write `research/bar_coverage.md`: how many of the 151 pairs have bars after this row, and an
explicit list of every pair still missing with the reason Polygon gave. A silent gap quietly
shrinks every later n.

- **done-when:** `research/bar_coverage.md` exists, states a covered count out of 151 within its first 10 lines, and explicitly lists every still-missing pair with a reason.

### T3 -- Feature vector at every marked bar

- model: glm
- depends-on: T2

For each row of `research/austin_marks_v2.jsonl`, load that day's bars from
`data_archive/<SYMBOL>/<DAY>.csv` and compute features at bar index `entry_i`. Skip and count any
row whose bars are missing per `research/bar_coverage.md`.

Use what exists rather than reimplementing: `research/levels.py` for the level set (HOD/LOD/swing/
psych, already excluding the entry bar) and root `predicates.py` for `is_break_and_retest`,
`is_order_block`, `is_84_reentry_opportunity`, `is_chop_market`, `is_x_signal`.

Features, at minimum:
- distance in R-multiples from the entry bar's close to the nearest level node above and below,
  and each one's weight
- the entry bar's body/range ratio, and its range over the median range of the prior 20 bars
  (displacement)
- bars elapsed since the level being retested was broken, where a break is identifiable
- `entry_i` itself - time of day is a real candidate, include it
- the boolean output of each predicate above
- whether the entry bar makes a new session high/low

**Leakage rule, and it voids the version if broken:** no feature may read any bar at index
> `entry_i`. State in the report how you enforced it, not that you intended to.

Write `research/mark_features.jsonl` (one row per usable mark: identity triple, tier, every
feature) and `research/mark_features.md` (usable count, dropped count, per-feature null count).

- **done-when:** `research/mark_features.jsonl` has one line per usable mark, each carrying symbol/day/entry_i/tier plus at least 8 named feature keys, and `research/mark_features.md` states the usable count, the dropped count, and how the no-future-bars rule was enforced.

### T4 -- Does the engine fire where Austin says S?

- model: glm
- depends-on: T2

Independent of T3 - reads only T1's and T2's outputs, so it runs alongside it.

Run the engine's own entry detection over the 151 marked `(symbol, day)` pairs and record every
entry it would take, with its bar index. Name in the report which module and function you used.

Join against `research/austin_marks_v2.jsonl` on `symbol|day`, tolerance +/-2 bars on the index:

- **Recall by tier:** of the 78 S marks, how many did the engine detect? Of the 60 A? Of the 24 X?
- **Precision:** of all engine entries on those days, what fraction land on a marked bar, and what
  is the tier mix of those that do?
- How many engine entries on marked days Austin did not mark at all.

Write `research/engine_recall.md` leading with the three recall numbers.

This is the cheapest decisive number in the version. If the engine misses most of the setups
Austin grades S, then no gate on the trades it already takes can help and the next version is a
detection problem, not a filter problem - and the verdict has to say so.

- **done-when:** `research/engine_recall.md` exists, states S/A/X recall counts and the precision fraction within its first 15 lines, and names the detection module and function it ran.

### T5 -- Fit the gate, and pre-register it before any backtest

- model: glm
- depends-on: T3

Read `research/mark_features.jsonl`. Do not recompute any feature.

Rank every feature by how well it separates **S from X** (n = 78 vs 24) and, separately, **S from
A** (n = 78 vs 60). Report for each: effect (Cohen's d for continuous, percentage-point difference
for booleans), a 95% CI from a block bootstrap over whole trading days with 10,000 resamples, and
a BH-FDR-adjusted p at q = 0.10. Report the minimum detectable effect at each arm's n, so a null
is distinguishable from an underpowered one. Flag any feature whose S/X separation reverses sign
against S/A - that one is measuring "obviously bad", not "his best".

Then define **one** gate:

- **At most two features.** n=24 on the X arm cannot support more; more than two is curve-fitting
  and the backtest in T7 will happily reward it.
- Thresholds from S/X quantiles, stated as literal numbers.
- It must clear the floor on **both** contrasts, or you state plainly that no gate qualifies.

Write `research/s_gate_spec.md`: the two ranked tables, then a **PRE-REGISTERED GATE** section
giving the exact predicate in one line of pseudocode, its literal thresholds, the fraction of S
marks it keeps and the fraction of X marks it rejects, and the prediction you are making about the
backtest. If no feature qualifies, say so explicitly and register the best-available gate anyway
with "does not clear the floor" stated in that section - T6 and T7 still run, and a negative A/B
on a pre-registered weak gate is a real result.

**Write this file before T6 or T7 touch anything.** The point is that the gate cannot be quietly
re-tuned after seeing the backtest.

- **done-when:** `research/s_gate_spec.md` exists, contains a ranked table for S-vs-X and one for S-vs-A each with effect/CI/FDR-p per feature, and contains a `PRE-REGISTERED GATE` section naming at most two features with literal numeric thresholds and a stated prediction.

### T6 -- Ship the gate into the engine

- model: glm
- depends-on: T5

This is the row that changes the code. Read `research/s_gate_spec.md` and implement exactly the
pre-registered gate - not your own improved version of it.

Follow the pattern the repo already uses for an A/B-able gate, documented in
`research/c1_displacement_gate_ab.md`: `BNR_DISPLACEMENT_GATE` is a **module global in
`signal_runner.py`, default OFF**, flipped at runtime by the harness. Do the same:

1. Add a predicate function to root `predicates.py` implementing the gate, taking the same
   `Candle` inputs as its neighbours and returning a bool. Docstring names
   `research/s_gate_spec.md` as its source and states the literal thresholds.
2. Add `S_GATE = False` as a module global in `signal_runner.py`, defaulting **OFF**, and wire it
   so that when True the gate is applied to candidate entries. Shipped default behaviour must be
   byte-identical to today.
3. Write `test_s_gate.py` at the repo root: plain asserts, no pytest. It must contain at least one
   case the gate accepts and one it rejects, constructed from the thresholds in the spec, plus one
   assertion that `S_GATE` defaults to False.

Do not change grading, sizing, exits, or anything the gate does not need.

- **done-when:** `python test_s_gate.py` exits 0, `grep -n "S_GATE" signal_runner.py` shows the module global defaulting to False, and the new predicate function exists in `predicates.py`.

### T7 -- A/B the gate on the 12-month backtest

- model: glm
- depends-on: T6

The number this whole version exists to produce.

Run `backtest_12mo.py 365` **twice** against the same Polygon 1-minute cache in `data_archive/`:
once with `S_GATE` OFF (the shipped default - this is the baseline) and once ON, flipping the
module global at runtime exactly as `research/c1_analyze.py` does for `BNR_DISPLACEMENT_GATE`.
Reuse `research/c1_analyze.py` / `b4_analyze.py` for the stats rather than writing new ones.

Set `PYTHONIOENCODING=utf-8` before every Python run.

Save `research/s_gate_off_run.log`, `research/s_gate_on_run.log`,
`research/s_gate_off_charts.json`, `research/s_gate_on_charts.json`.

Write `research/s_gate_ab.md` in the same shape as `research/c1_displacement_gate_ab.md`:

- a **mechanism check first** - signal and chart counts for both runs, proving the flag actually
  took effect. If the two runs are identical, the gate never fired and everything below is void;
  say that instead of reporting a null.
- headline table: traded count, win rate, total P&L, avg R, for OFF and ON, with the delta
- P&L and win rate by grade for both runs
- the **difference in avg R with a 95% CI from a block bootstrap over whole trading days**, and
  whether it clears the 4-point / d=0.15 floor
- how many trades the gate removed and what those removed trades did as a group - a gate that
  removes losers is the point; a gate that removes winners at the same rate is noise

- **done-when:** `research/s_gate_ab.md` exists, its first 20 lines carry the mechanism check with signal counts for both runs, and it contains a headline table with traded count / win rate / P&L / avg R for OFF and ON plus a CI on the difference.

### T8 -- Verdict

- model: opus
- depends-on: everything

Read `research/austin_marks_v2.md`, `research/bar_coverage.md`, `research/mark_features.md`,
`research/engine_recall.md`, `research/s_gate_spec.md`, `research/s_gate_ab.md`. **Do not
recompute any number.**

Answer, in order:

1. **Did the gate move the backtest?** Give OFF vs ON avg R and win rate with the CI on the
   difference. State whether it clears the floor. If the mechanism check in T7 shows the flag did
   not take effect, that is the answer and nothing else in T7 is admissible.
2. **Is that number trustworthy?** The gate was fit on the marks and tested on the engine's 1,289
   trades, which are different samples - say so, and also name what is still shared between them
   (same symbols, overlapping date range) and what that does to the claim.
3. **Does the engine find Austin's S setups at all?** Give the recall figure and say what it
   implies: is OMEN's problem picking better among the trades it takes, or finding trades it
   currently misses?
4. **Are we closer to an edge?** Against the +0.146R / 38.0% baseline and the 33.333% breakeven,
   in win-rate points, with the CI. Do not report a point estimate without its interval.
5. **The one change to make next** - one concrete thing, or state plainly that nothing testable is
   left in this thread and name what data would be needed instead.

Write `research/v36_verdict.md`, ending with a `FOR AUSTIN` section of ten lines or fewer, written
for someone who trades this tomorrow and will not open any other file.

- **done-when:** `research/v36_verdict.md` exists, answers all five numbered questions in order, and ends with a `FOR AUSTIN` section of ten lines or fewer.

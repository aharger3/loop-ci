# OMEN 3.6 - Austin's 78 S trades as labels

status: ready
version: omen-3.6
repo: aharger3/tradingbot
doc: Projects/omen-trading.md

target: test what separates the 78 entries Austin graded S from the 24 he graded X, using his
verdicts as ground-truth labels on specific 1-minute bars, and measure whether the engine even
fires at the bars he likes.

Framing, so no row re-derives it. Austin hand-graded 162 entries, `s`/`a`/`x`. 3.5 tried to
apply them as a re-grade of `research/blind_marks_all.jsonl` and matched **0 of 162** - the two
sets share zero `(symbol, day)` pairs, so they are a second, independent marking session over a
different sample of chart-days, not a re-grade. That premise is dead; do not retry it.

What makes them usable anyway: **`entry_i` is minutes since 09:30**, verified against all 117
`entry_t` values in the existing corpus with zero mismatches. So every verdict resolves to an
exact 1-minute bar from `(symbol, day, entry_i)` and needs no chart manifest, no marking-tool
export, and no corpus merge. The 162 rows are labels over bars. That is the whole idea of this
version.

These are labels for refining the engine, not corpus rows. **No row may merge a single one of the
162 verdicts into `research/blind_marks_all.jsonl` or `research/marks_clean.jsonl`** - the two
marking sessions are separate samples and mixing them would silently pool them. (T3 does rewrite
`marks_clean.jsonl`, but only with defect flags computed from the OLD corpus's own rows.)

Statistical floor, not to be renegotiated inside a row: **4 percentage points of win rate, or
Cohen's d = 0.15**. Block-bootstrap over whole trading days (10,000 resamples) for every CI.
Correct multiple hypotheses with **BH-FDR at q = 0.10**. n is small on the X arm (24) - a row
that finds nothing must say "underpowered at n=24" rather than "no effect", and report the
minimum detectable effect it actually had.

`research/levels.py` on main already carries 3.5's HOD/LOD fix (`seg = bars[: entry_i]`, merged
2026-08-06 with `research/test_levels.py` passing). Do not re-apply it.

## Tasks

### T1 -- Normalize the 162 verdicts into a labels file

- model: glm

The verdicts are the JSON array below - 162 objects, each `{"symbol","day","entry_i","verdict"}`
where verdict is `s`, `a`, or `x`. It is inline here on purpose: rows share no memory, and this
array is the only copy that exists anywhere in either repo. Write it out verbatim first, to
`research/austin_verdicts.json`, before you transform anything - later rows depend on it existing
and you are the only row that can see it.

```json
[{"symbol":"HOOD","day":"2025-08-04","entry_i":40,"verdict":"a"},{"symbol":"SOFI","day":"2026-03-11","entry_i":63,"verdict":"a"},{"symbol":"QQQ","day":"2025-06-25","entry_i":48,"verdict":"a"},{"symbol":"SPY","day":"2026-01-08","entry_i":42,"verdict":"x"},{"symbol":"MSFT","day":"2026-02-11","entry_i":20,"verdict":"a"},{"symbol":"QQQ","day":"2025-02-26","entry_i":28,"verdict":"s"},{"symbol":"SPY","day":"2026-02-09","entry_i":24,"verdict":"a"},{"symbol":"HOOD","day":"2026-05-19","entry_i":19,"verdict":"a"},{"symbol":"META","day":"2025-09-23","entry_i":9,"verdict":"a"},{"symbol":"NVDA","day":"2024-11-19","entry_i":18,"verdict":"a"},{"symbol":"COIN","day":"2025-10-21","entry_i":8,"verdict":"s"},{"symbol":"IWM","day":"2026-07-24","entry_i":29,"verdict":"s"},{"symbol":"QQQ","day":"2025-06-24","entry_i":15,"verdict":"s"},{"symbol":"META","day":"2026-06-10","entry_i":18,"verdict":"x"},{"symbol":"SPY","day":"2024-10-22","entry_i":41,"verdict":"a"},{"symbol":"MARA","day":"2025-08-18","entry_i":23,"verdict":"x"},{"symbol":"IWM","day":"2024-04-03","entry_i":13,"verdict":"s"},{"symbol":"IWM","day":"2024-04-03","entry_i":73,"verdict":"s"},{"symbol":"IWM","day":"2024-04-03","entry_i":73,"verdict":"s"},{"symbol":"AMZN","day":"2025-08-14","entry_i":18,"verdict":"x"},{"symbol":"CRM","day":"2025-07-02","entry_i":17,"verdict":"a"},{"symbol":"MARA","day":"2025-04-02","entry_i":14,"verdict":"a"},{"symbol":"BABA","day":"2025-07-22","entry_i":20,"verdict":"s"},{"symbol":"TSM","day":"2025-10-07","entry_i":74,"verdict":"a"},{"symbol":"QQQ","day":"2024-12-23","entry_i":47,"verdict":"a"},{"symbol":"CRM","day":"2026-05-07","entry_i":18,"verdict":"x"},{"symbol":"IWM","day":"2025-12-01","entry_i":11,"verdict":"s"},{"symbol":"SPY","day":"2026-03-25","entry_i":10,"verdict":"x"},{"symbol":"AMD","day":"2026-04-21","entry_i":35,"verdict":"a"},{"symbol":"GOOGL","day":"2025-08-07","entry_i":18,"verdict":"s"},{"symbol":"QQQ","day":"2024-05-08","entry_i":8,"verdict":"s"},{"symbol":"HOOD","day":"2025-03-04","entry_i":44,"verdict":"s"},{"symbol":"INTC","day":"2025-06-05","entry_i":10,"verdict":"x"},{"symbol":"QQQ","day":"2024-03-05","entry_i":11,"verdict":"a"},{"symbol":"QQQ","day":"2024-03-05","entry_i":21,"verdict":"s"},{"symbol":"QQQ","day":"2025-03-17","entry_i":16,"verdict":"s"},{"symbol":"SPY","day":"2024-04-03","entry_i":9,"verdict":"s"},{"symbol":"GOOG","day":"2025-06-10","entry_i":21,"verdict":"a"},{"symbol":"QQQ","day":"2026-02-11","entry_i":32,"verdict":"s"},{"symbol":"QQQ","day":"2026-02-11","entry_i":45,"verdict":"s"},{"symbol":"SPY","day":"2025-02-21","entry_i":18,"verdict":"x"},{"symbol":"IWM","day":"2025-09-05","entry_i":12,"verdict":"s"},{"symbol":"IWM","day":"2025-09-05","entry_i":51,"verdict":"a"},{"symbol":"QQQ","day":"2025-12-05","entry_i":27,"verdict":"s"},{"symbol":"QQQ","day":"2025-12-05","entry_i":35,"verdict":"s"},{"symbol":"CRM","day":"2025-06-02","entry_i":27,"verdict":"s"},{"symbol":"QQQ","day":"2025-03-18","entry_i":13,"verdict":"s"},{"symbol":"SPY","day":"2025-06-02","entry_i":40,"verdict":"a"},{"symbol":"QQQ","day":"2024-01-04","entry_i":41,"verdict":"s"},{"symbol":"MSFT","day":"2026-01-20","entry_i":12,"verdict":"s"},{"symbol":"IWM","day":"2024-02-28","entry_i":9,"verdict":"s"},{"symbol":"IWM","day":"2024-02-28","entry_i":18,"verdict":"a"},{"symbol":"AMZN","day":"2026-07-17","entry_i":7,"verdict":"a"},{"symbol":"COIN","day":"2026-03-04","entry_i":43,"verdict":"a"},{"symbol":"MU","day":"2025-11-07","entry_i":22,"verdict":"s"},{"symbol":"QQQ","day":"2025-01-16","entry_i":23,"verdict":"s"},{"symbol":"QQQ","day":"2025-12-30","entry_i":24,"verdict":"s"},{"symbol":"GOOG","day":"2025-12-08","entry_i":58,"verdict":"x"},{"symbol":"TSLA","day":"2026-02-18","entry_i":42,"verdict":"s"},{"symbol":"QQQ","day":"2024-10-03","entry_i":18,"verdict":"s"},{"symbol":"UBER","day":"2026-06-09","entry_i":11,"verdict":"a"},{"symbol":"NVDA","day":"2024-11-18","entry_i":10,"verdict":"s"},{"symbol":"QQQ","day":"2025-05-16","entry_i":63,"verdict":"a"},{"symbol":"IWM","day":"2025-04-10","entry_i":16,"verdict":"s"},{"symbol":"MARA","day":"2025-05-14","entry_i":23,"verdict":"x"},{"symbol":"GOOGL","day":"2024-09-03","entry_i":10,"verdict":"a"},{"symbol":"ORCL","day":"2025-11-03","entry_i":17,"verdict":"s"},{"symbol":"ORCL","day":"2025-03-28","entry_i":12,"verdict":"s"},{"symbol":"IWM","day":"2025-10-21","entry_i":9,"verdict":"s"},{"symbol":"HOOD","day":"2025-02-24","entry_i":16,"verdict":"a"},{"symbol":"QQQ","day":"2024-08-23","entry_i":36,"verdict":"s"},{"symbol":"UBER","day":"2025-09-11","entry_i":15,"verdict":"s"},{"symbol":"GOOGL","day":"2024-10-15","entry_i":32,"verdict":"s"},{"symbol":"NVDA","day":"2024-12-16","entry_i":12,"verdict":"a"},{"symbol":"MSFT","day":"2025-03-04","entry_i":13,"verdict":"s"},{"symbol":"QQQ","day":"2025-01-10","entry_i":13,"verdict":"s"},{"symbol":"TSLA","day":"2024-03-27","entry_i":13,"verdict":"s"},{"symbol":"QQQ","day":"2026-03-04","entry_i":42,"verdict":"s"},{"symbol":"MARA","day":"2026-07-09","entry_i":19,"verdict":"s"},{"symbol":"CRM","day":"2025-11-18","entry_i":16,"verdict":"a"},{"symbol":"NVDA","day":"2024-12-30","entry_i":34,"verdict":"a"},{"symbol":"MU","day":"2026-01-28","entry_i":13,"verdict":"s"},{"symbol":"SPY","day":"2025-09-25","entry_i":45,"verdict":"a"},{"symbol":"HOOD","day":"2026-04-13","entry_i":16,"verdict":"s"},{"symbol":"SPY","day":"2025-02-20","entry_i":35,"verdict":"a"},{"symbol":"TSM","day":"2026-05-29","entry_i":23,"verdict":"s"},{"symbol":"GOOG","day":"2026-02-23","entry_i":19,"verdict":"x"},{"symbol":"MARA","day":"2026-07-17","entry_i":13,"verdict":"a"},{"symbol":"SPY","day":"2024-02-22","entry_i":25,"verdict":"a"},{"symbol":"UBER","day":"2026-01-06","entry_i":22,"verdict":"a"},{"symbol":"SPY","day":"2025-11-05","entry_i":52,"verdict":"a"},{"symbol":"QQQ","day":"2024-02-01","entry_i":44,"verdict":"x"},{"symbol":"SPY","day":"2026-03-03","entry_i":17,"verdict":"s"},{"symbol":"IWM","day":"2024-03-22","entry_i":24,"verdict":"s"},{"symbol":"SPY","day":"2025-03-18","entry_i":13,"verdict":"s"},{"symbol":"PLTR","day":"2024-10-23","entry_i":21,"verdict":"s"},{"symbol":"QQQ","day":"2026-07-09","entry_i":11,"verdict":"s"},{"symbol":"ORCL","day":"2026-06-09","entry_i":8,"verdict":"a"},{"symbol":"SPY","day":"2026-05-05","entry_i":10,"verdict":"a"},{"symbol":"AMD","day":"2026-05-14","entry_i":25,"verdict":"a"},{"symbol":"HOOD","day":"2026-02-05","entry_i":40,"verdict":"s"},{"symbol":"TSLA","day":"2024-12-03","entry_i":8,"verdict":"a"},{"symbol":"IWM","day":"2024-08-22","entry_i":27,"verdict":"s"},{"symbol":"COIN","day":"2025-12-01","entry_i":11,"verdict":"a"},{"symbol":"QQQ","day":"2024-01-30","entry_i":35,"verdict":"x"},{"symbol":"ORCL","day":"2025-07-08","entry_i":7,"verdict":"s"},{"symbol":"TSLA","day":"2024-06-24","entry_i":9,"verdict":"s"},{"symbol":"UBER","day":"2026-07-06","entry_i":12,"verdict":"s"},{"symbol":"QQQ","day":"2026-03-06","entry_i":47,"verdict":"x"},{"symbol":"MARA","day":"2025-07-30","entry_i":30,"verdict":"a"},{"symbol":"MARA","day":"2024-09-09","entry_i":38,"verdict":"x"},{"symbol":"IWM","day":"2026-06-24","entry_i":28,"verdict":"a"},{"symbol":"MARA","day":"2024-10-18","entry_i":11,"verdict":"s"},{"symbol":"HOOD","day":"2026-07-07","entry_i":37,"verdict":"a"},{"symbol":"TSLA","day":"2024-02-05","entry_i":16,"verdict":"a"},{"symbol":"MU","day":"2025-12-08","entry_i":12,"verdict":"x"},{"symbol":"UBER","day":"2025-07-31","entry_i":48,"verdict":"a"},{"symbol":"PLTR","day":"2026-03-31","entry_i":23,"verdict":"s"},{"symbol":"IWM","day":"2026-05-28","entry_i":46,"verdict":"s"},{"symbol":"MARA","day":"2024-12-17","entry_i":49,"verdict":"s"},{"symbol":"SPY","day":"2025-12-02","entry_i":14,"verdict":"x"},{"symbol":"AMD","day":"2025-06-05","entry_i":6,"verdict":"s"},{"symbol":"IWM","day":"2024-08-01","entry_i":44,"verdict":"a"},{"symbol":"QQQ","day":"2024-03-15","entry_i":11,"verdict":"s"},{"symbol":"MSFT","day":"2026-06-10","entry_i":17,"verdict":"a"},{"symbol":"UBER","day":"2025-02-07","entry_i":22,"verdict":"s"},{"symbol":"CRM","day":"2025-09-26","entry_i":12,"verdict":"a"},{"symbol":"PLTR","day":"2025-09-18","entry_i":14,"verdict":"s"},{"symbol":"SOFI","day":"2024-10-30","entry_i":16,"verdict":"s"},{"symbol":"QQQ","day":"2025-01-28","entry_i":40,"verdict":"a"},{"symbol":"QQQ","day":"2024-12-16","entry_i":28,"verdict":"s"},{"symbol":"MARA","day":"2026-07-20","entry_i":11,"verdict":"a"},{"symbol":"SOFI","day":"2026-05-20","entry_i":55,"verdict":"a"},{"symbol":"NVDA","day":"2025-03-25","entry_i":25,"verdict":"a"},{"symbol":"COIN","day":"2025-06-26","entry_i":18,"verdict":"s"},{"symbol":"TSLA","day":"2024-01-12","entry_i":18,"verdict":"x"},{"symbol":"QQQ","day":"2025-05-07","entry_i":31,"verdict":"a"},{"symbol":"HOOD","day":"2025-12-29","entry_i":12,"verdict":"x"},{"symbol":"ORCL","day":"2025-09-17","entry_i":11,"verdict":"a"},{"symbol":"AMD","day":"2026-03-04","entry_i":9,"verdict":"a"},{"symbol":"AMZN","day":"2026-04-10","entry_i":74,"verdict":"a"},{"symbol":"UBER","day":"2025-08-13","entry_i":25,"verdict":"s"},{"symbol":"IWM","day":"2025-12-04","entry_i":56,"verdict":"s"},{"symbol":"IWM","day":"2024-09-24","entry_i":35,"verdict":"x"},{"symbol":"IWM","day":"2024-09-24","entry_i":53,"verdict":"x"},{"symbol":"HOOD","day":"2026-07-10","entry_i":23,"verdict":"s"},{"symbol":"SPY","day":"2025-07-01","entry_i":41,"verdict":"a"},{"symbol":"GOOG","day":"2025-04-04","entry_i":26,"verdict":"a"},{"symbol":"SPY","day":"2024-06-11","entry_i":23,"verdict":"s"},{"symbol":"SPY","day":"2026-03-02","entry_i":24,"verdict":"s"},{"symbol":"COIN","day":"2026-04-09","entry_i":30,"verdict":"s"},{"symbol":"SPY","day":"2026-03-05","entry_i":56,"verdict":"s"},{"symbol":"NVDA","day":"2026-05-21","entry_i":10,"verdict":"a"},{"symbol":"MSFT","day":"2025-03-20","entry_i":28,"verdict":"s"},{"symbol":"BABA","day":"2025-12-26","entry_i":36,"verdict":"a"},{"symbol":"QQQ","day":"2025-07-01","entry_i":72,"verdict":"x"},{"symbol":"QQQ","day":"2025-07-01","entry_i":72,"verdict":"x"},{"symbol":"QQQ","day":"2025-07-01","entry_i":72,"verdict":"x"},{"symbol":"SPY","day":"2025-11-19","entry_i":9,"verdict":"s"},{"symbol":"SPY","day":"2024-09-19","entry_i":19,"verdict":"s"},{"symbol":"QQQ","day":"2025-02-25","entry_i":16,"verdict":"s"},{"symbol":"QQQ","day":"2025-02-25","entry_i":53,"verdict":"a"}]
```

Write `research/austin_marks_v2.jsonl`, one JSON object per line:
`{"symbol", "day", "entry_i", "tier"}` with tier uppercased to S/A/X.

Rules:
- Identity is the triple `symbol|day|entry_i`. There are **3 duplicate triples** in the input
  (159 unique of 162). Keep the LAST occurrence in file order; do not error.
- Assert `0 <= entry_i <= 390` on every row and fail loudly listing any row outside it.

Also write `research/austin_marks_v2.md`: the S/A/X counts, the count of distinct
`(symbol, day)`, the duplicate triples you collapsed, and the entry_i min/max.

- **done-when:** `research/austin_verdicts.json` has 162 objects, `research/austin_marks_v2.jsonl` has exactly 159 lines with keys symbol/day/entry_i/tier and tier in S/A/X, and `research/austin_marks_v2.md` states the three tier counts and sums them to 159.

### T2 -- Close the 1-minute bar gap for the marked days

- model: glm
- depends-on: T1

The marks cover 151 distinct `(symbol, day)` pairs. **102 already have bars on disk** at
`data_archive/<SYMBOL>/<YYYY-MM-DD>.csv`; **49 do not.** Note that `IWM` appears in the marks
but is absent from `archive_1m.py`'s `SYMBOLS` list, so none of its days are banked.

Read the pairs from `research/austin_marks_v2.jsonl`, which T1 wrote.

For every missing pair, fetch the day with `polygon_feed.fetch_day()` (it caches into the same
`data_archive/<SYM>/<DAY>.csv` layout, so a second call is a disk read at zero API cost). Do not
use yfinance for anything; it is a settled-dead dependency on this project.

Write `research/bar_coverage.md`: how many of the 151 pairs have bars after this row ran, and an
explicit list of every pair still missing with the reason Polygon gave (no data for that date,
symbol not covered, rate limit, etc.). A silent gap here quietly shrinks every later n.

- **done-when:** `research/bar_coverage.md` exists, states a covered count out of 151 in its first 10 lines, and explicitly lists every still-missing pair with a reason.

### T3 -- Mark-defect audit on the OLD corpus (owed since 3.4, never delivered)

- model: glm

This has been checked `[x]` on two prior runs and has never produced its file. Do it for real.
It is about the OLD corpus, `research/blind_marks_all.jsonl` - not the new labels.

For every mark in `research/blind_marks_all.jsonl` that carries a tier, compute three booleans:

- `smeared`: shares a `symbol|day|marked_at` with at least one other mark (per-chart tier/tags
  were captured once per chart and copied onto every entry from that chart).
- `incoherent`: `side == "call"` and `target <= entry`, or `side == "put"` and `target >= entry`.
- `sub_1r`: `rr < 1.0`.

Write `research/marks_audit.md` with a count for each defect and the median `rr`. Overwrite
`research/marks_clean.jsonl` with every tiered mark carrying all three booleans alongside its
existing fields.

This matters because `research/h9_confluence.py` reads `marks_clean.jsonl`: if smearing is
widespread, H9's inputs were never independent observations and its whole result is suspect.
Say so plainly in the file if the smeared count is large.

- **done-when:** `research/marks_audit.md` exists and states a count for each of the three defects plus the median rr, and every line in `research/marks_clean.jsonl` has `smeared`, `incoherent`, and `sub_1r` keys.

### T4 -- Extract a feature vector at every marked bar

- model: glm
- depends-on: T1, T2

For each row of `research/austin_marks_v2.jsonl`, load that day's bars from
`data_archive/<SYMBOL>/<DAY>.csv` and compute a feature vector at bar index `entry_i`, using
only information available at or before that bar. Skip (and count) any row whose bars are
missing per `research/bar_coverage.md`.

Use the existing modules rather than reimplementing them: `research/levels.py` for the level set
(HOD/LOD/swing/psych, already fixed to exclude the entry bar) and `research/predicates.py` for
the rule predicates (break-and-retest, order-block, x-reject).

Features, at minimum - add more if the code already computes them cheaply:
- distance in R-multiples from the entry bar's close to the nearest level node above and below,
  and the weight of each
- the entry bar's body/range ratio, and its range relative to the median range of the prior
  20 bars (displacement)
- bars elapsed since the level being retested was broken, if a break is identifiable
- minutes since 09:30 (that is `entry_i` itself - include it, time of day is a real candidate)
- the boolean output of each predicate in `predicates.py`
- prior-session-extreme context: is the entry bar making a new HOD/LOD

**Leakage rule, and it is the one that voids a version if broken:** no feature may read any bar
at index > `entry_i`. State in the report how you enforced this, not that you intended to.

Write `research/mark_features.jsonl` (one row per usable mark: the identity triple, the tier, and
every feature) and `research/mark_features.md` (row count, rows dropped for missing bars, and
per-feature the count of nulls).

- **done-when:** `research/mark_features.jsonl` exists with one line per usable mark, each line carrying symbol/day/entry_i/tier plus at least 8 named feature keys, and `research/mark_features.md` states the usable-row count, the dropped-row count, and how the no-future-bars rule was enforced.

### T5 -- Does the engine fire where Austin says S?

- model: glm
- depends-on: T1, T2

Independent of T4 - it reads only T1's and T2's outputs, so it runs alongside it.

Run the existing detection path (`research/backtest.py` / the scanner's signal detection, whichever
is the current entry-detection code - name in the report which module and function you used) over
the 151 marked `(symbol, day)` pairs and record every entry it would have taken, with its bar index.

Then join against `research/austin_marks_v2.jsonl` on `symbol|day` and report, with a tolerance of
+/-2 bars on the index:

- **Recall by tier:** of the 78 S marks, how many did the engine detect? Of the 60 A? Of the 24 X?
- **Precision:** of all engine entries on those days, what fraction land on a marked bar, and what
  is the tier mix of the ones that do?
- The count of engine entries on marked days that Austin did not mark at all.

Write `research/engine_recall.md`, leading with the three recall numbers.

This is the cheapest high-value number in the version: if the engine misses most of the setups
Austin grades S, no amount of gate-tuning on the trades it already takes can help, and the next
version is a detection problem rather than a filter problem.

- **done-when:** `research/engine_recall.md` exists, states S/A/X recall counts and the precision fraction within its first 15 lines, and names the detection module and function it ran.

### T6 -- Re-run H3 and H9 against the fixed levels.py

- model: glm
- depends-on: T3

3.4 killed the wall-veto as *operationalised*, not as an idea: `hod_lod_nodes()` computed the
session extreme through the entry bar, so the nearest wall was the entry bar's own extreme in
96.9% of trades and the veto fired at 42-64%, outside its own 5-40% validity band. That fix is
now on main. Nobody has re-run the hypotheses against it.

Re-run `research/h3_veto.py` and `research/h9_confluence.py` unchanged, against the current
`research/levels.py` and the `research/marks_clean.jsonl` that T3 just rewrote. Same four-threshold
sweep for H3 (0.8R/1.0R/1.2R/1.5R), same weight-bucket table for H9. Copy the existing
`research/h3_veto.md` and `research/h9_confluence.md` to `research/h3_veto.PRE-FIX.md` and
`research/h9_confluence.PRE-FIX.md` BEFORE overwriting them, so the before/after is on disk.

At the top of each new file state: the veto rate at each threshold (validity band is 5-40%; if it
is still outside, the HOD/LOD fix was not the whole problem and say so plainly), and how many of
H9's weight-bucket assignments changed versus PRE-FIX.

- **done-when:** `research/h3_veto.md`, `research/h9_confluence.md`, `research/h3_veto.PRE-FIX.md` and `research/h9_confluence.PRE-FIX.md` all exist, and each of the two new files states its veto rate or bucket-change count within its first 10 lines.

### T7 -- What separates S from X

- model: glm
- depends-on: T4

Read `research/mark_features.jsonl`. Do not recompute any feature.

Two contrasts, both reported:
1. **S vs X** - the clean contrast, n = 78 vs 24. Small, and the reason for the floor.
2. **S vs A** - the harder and larger contrast, n = 78 vs 60. If a feature separates S from X but
   not S from A, it is measuring "obviously bad" rather than "his best".

For every feature: the effect (difference in means with Cohen's d for continuous features, or
difference in rate in percentage points for booleans), a 95% CI from a block bootstrap over whole
trading days with 10,000 resamples, and a BH-FDR-adjusted p at q = 0.10.

Report the **minimum detectable effect** at each arm's n, so a null result is distinguishable from
an underpowered one. Explicitly flag any feature whose S/X separation reverses sign against S/A.

Write `research/mark_separation.md`: one table per contrast, ranked by effect size, with a plain
one-line verdict per feature (clears the floor and survives FDR / clears the floor but not FDR /
below the floor / underpowered).

- **done-when:** `research/mark_separation.md` exists, contains one ranked table for S-vs-X and one for S-vs-A with an effect, a CI and an FDR-adjusted p on every feature row, and states the minimum detectable effect for each contrast.

### T8 -- Verdict

- model: opus
- depends-on: everything

Read `research/austin_marks_v2.md`, `research/bar_coverage.md`, `research/marks_audit.md`,
`research/mark_features.md`, `research/engine_recall.md`, `research/mark_separation.md`,
`research/h3_veto.md`, `research/h9_confluence.md`, and the two `.PRE-FIX.md` files. **Do not
recompute any number.**

Answer, in order:

1. **Does the engine find Austin's S setups at all?** Give the recall figure and say what it
   implies: is OMEN's problem picking better among the trades it takes, or finding trades it
   currently misses entirely?
2. **Does anything separate S from X, and does it survive S vs A?** Name every feature that clears
   the floor AND survives BH-FDR on both contrasts. If none does, say whether that is a null result
   or an underpowered one, using T7's minimum detectable effects - do not blur the two.
3. **Did the HOD/LOD fix revive H3 or H9?** State whether the veto rate is now inside its 5-40%
   band, and whether 3.4's "0 of 8 cleared" count changed.
4. **Is the old corpus sound?** If T3 found widespread smearing, say what that does to every prior
   result that read `marks_clean.jsonl`.
5. **The one change to make next.** One concrete thing - or state plainly that nothing testable is
   left in this thread and name what data would be needed instead.

Write `research/v36_verdict.md`, ending with a `FOR AUSTIN` section of ten lines or fewer, written
for someone who trades this tomorrow and will not open any of the other files.

- **done-when:** `research/v36_verdict.md` exists, answers all five numbered questions in order, and ends with a `FOR AUSTIN` section of ten lines or fewer.

# OMEN 3.4 - level context as a filter

status: ready
version: omen-3.4
repo: aharger3/tradingbot
doc: Projects/omen-trading.md

target: decide whether higher-timeframe level context earns a place in OMEN, by measuring it against the trade population that already exists on disk - and by learning Austin's real target rule from his marks instead of asking him again.

Framing, so no row re-derives it: mechanical entry rules were settled negative on 2026-08-04. The
prior for this version is therefore that level context is a **filter that removes bad trades**, not a
generator that finds new ones. Rows that measure removal are the valuable ones. A negative result is
a real result here and must be reported as one, not softened.

Two numbers govern every statistical row and are not to be renegotiated inside a row:
- **Effect-size floor: 4 percentage points of win rate, or Cohen's d = 0.15.** Smaller than that does
  not survive slippage and does not change how the account is traded. Report it, do not build on it.
- **Trades are clustered by day.** Three index trades in one morning are not three independent
  observations. Every confidence interval comes from a **block bootstrap over whole trading days**
  (10,000 resamples), never from a textbook variance formula. Report the estimated ICC.

Where multiple hypotheses are tested, correct with **Benjamini-Hochberg FDR at q = 0.10**, not
Bonferroni. Prefer continuous endpoints (MFE in R) over binary win/loss wherever both are available -
detecting d = 0.20 needs roughly 786 trades where a 5-point win-rate difference needs over 3,000.

## Tasks

### T1 -- Inventory and freeze the population

- model: deepseek

Nothing downstream may guess a path or a row count. Find, on the checked-out repo, the real location
and size of each of: the engine trade population (`backtest_metrics_full.json` is at the repo ROOT,
not under `research/`), the predicate module (`predicates.py`, also at root), the 1-minute bar
material (`backtest_charts.json`, `backtest_charts_12mo.json`, and anything under `.cache/`), and the
hand-marked corpus (`research/blind_marks_all.jsonl`).

For each: absolute repo-relative path, byte size, and the number of records it actually contains -
counted by parsing it, never inferred from a filename or a doc. Where a file named in the vault docs
does not exist in the repo, say so explicitly under a heading `MISSING`.

Write `research/omen34_inputs.md`. Every later row reads this file to learn its paths and must not
hardcode any path this file contradicts. State one integer as `POPULATION_N:` on its own line - the
count of trades in the engine population. That integer is the denominator for the whole version.

Prior docs quote the same artifact as 875, 1,289, 1,982, 2,061 and 63,520 trades. Do not reconcile
those numbers by argument. Count the file and report what it says.

- **done-when:** `research/omen34_inputs.md` exists, contains a line matching `^POPULATION_N: [0-9]+$`, and every path it lists outside its `MISSING` section resolves to a file that exists.

### T2 -- Level engine

- model: glm
- depends-on: T1

Write `research/levels.py`: given a symbol, a date, and 1-minute bars, return the level set for that
session. Read paths from `research/omen34_inputs.md`.

Levels to compute, each with a precise definition and a confluence weight:

| level | definition | weight |
|---|---|---|
| PDH / PDL | prior session regular-hours high / low | 3.0 |
| PDC | prior session close | 2.0 |
| PMH / PML | 04:00-09:29 ET high / low | 2.0 |
| ORH / ORL | 09:30-09:34 high / low (5 bars, matching the marking tool) | 2.0 |
| HOD / LOD | running session extreme, recomputed every bar | 3.0 |
| round whole | nearest whole number; increment scales with price - 0.50 under $25, 1.00 for $25-250, 5.00 above $250 | 2.0 |
| round half | the half-step between whole numbers | 1.0 |
| swing pivot | fractal high/low with N=3 bars either side, confirmed only after N bars have closed | 1.0 |

Two rules that decide whether this module is honest:

**No lookahead.** A level carries an `available_from` timestamp and may never be returned for a bar
earlier than it. HOD at 09:41 is the high of 09:30-09:41 only. A confirmed N=3 pivot is not available
until 3 bars after its apex. A module that returns the session's final HOD for a 09:41 query is
worthless and will make every downstream row report a fake edge.

**Cluster before use.** Levels within `max(2 ticks, 0.30 x ATR_1m_14)` of each other are one node
whose weight is the sum of its members. A round number sitting on the PDH is one wall, not two.

Seed ATR_1m_14 from the prior session's last 14 bars so the first ten minutes are not measured against
an undefined denominator.

Write `research/test_levels.py` as an assert script - no pytest. It must include a case proving a
pivot is unavailable before its confirmation bar, and a case proving two levels 1 tick apart merge
into one node whose weight is the sum.

- **done-when:** `python research/test_levels.py` exits 0, and `python research/levels.py --selftest` prints a level set for one symbol-day with every entry carrying an `available_from` field.

### T3 -- Ingest the marks and audit their coherence

- model: deepseek
- depends-on: T1

Read the marks corpus named in `research/omen34_inputs.md`. Write
`research/marks_audit.md` plus `research/marks_clean.jsonl`.

Identity for a mark is the triple `symbol|day|entry_i`. Re-importing the same export must be a no-op.

The marking tool has three known defects and this row's job is to quantify them, not fix them:

1. **Per-chart smear.** Tier, setup tags and note were captured once per chart and copied onto every
   entry from that chart. Count how many marks are affected - i.e. how many share a
   `symbol|day|marked_at` with at least one other mark. Those marks have an unreliable tier.
2. **Incoherent direction.** `side` was inferred from stop position alone and `rr` used an absolute
   value, so a target on the wrong side of entry scores as positive. Flag every mark where
   `side == "call"` and `target <= entry`, or `side == "put"` and `target >= entry`. At least one such
   mark exists (BABA 2024-08-05, entry 74.97, target 74.82, scored 0.65R). List them all.
3. **Sub-1R targets.** Flag every mark with `rr < 1.0` and report the count and the median rr of the
   whole set. A target below 1R cannot reach the stated goal and is more likely a mislabel than a trade.

Emit `research/marks_clean.jsonl` with every mark carrying three added booleans: `smeared`,
`incoherent`, `sub_1r`. Do not drop anything - downstream rows decide what to exclude.

- **done-when:** `research/marks_clean.jsonl` has exactly one line per input mark, every line carries the three boolean fields, and `research/marks_audit.md` states a count for each of the three defects.

### T4 -- Target autopsy: what rule is he actually using

- model: deepseek
- depends-on: T2, T3

The headline row of this version. He describes his targets as "usually 2R, HOD/LOD and whole
psychological numbers, as well as longer timeframe levels and pivot structures." That is four rules
with no stated precedence. Find the precedence from the data.

For every mark in `research/marks_clean.jsonl`, compute the level node set at its entry bar using
`research/levels.py`, then classify its target: which node is it nearest to, how far in ticks and in
ATR, and what is that node's type and weight. Classify each target into exactly one bucket -
`at_level`, `at_2R`, `both`, `open_air` - where `at_2R` means within 0.25R of exactly 2.0R and
`at_level` means within `max(2 ticks, 0.30 x ATR_1m)` of a node of weight >= 2.0.

Then answer, in `research/target_autopsy.md`:

- The bucket distribution, split by tier and by `smeared` - if smeared marks distribute differently
  from clean ones, the tier labels are contaminated and the report must say so.
- When a level and 2R disagree, which one does he take? This is the precedence question.
- Distance from target to the nearest node, as a distribution in ticks. If targets cluster **just
  short** of round numbers, that is Osler's queue effect showing up in his hand and it is directly
  actionable; if they sit exactly on them, it is not.
- The rr distribution: median, quartiles, and the fraction below 1.0 and above 5.0.

Every mark must land in a bucket. A mark the code cannot classify is a bug in the classifier, not an
`unknown` row - if any mark is unclassifiable, fail loudly and say which.

- **done-when:** `research/target_autopsy.md` exists, reports a bucket count for all four buckets summing to the line count of `research/marks_clean.jsonl`, and contains a section headed `PRECEDENCE` naming which rule wins when a level and 2R disagree.

### T5 -- H5: does targeting just short of a round number fill more often

- model: deepseek
- depends-on: T2

A pure resimulation over the existing population - no new data, no human input. Osler (2003) found
take-profit orders cluster at round numbers and stops cluster just beyond them, so a limit resting
exactly at a round number sits behind a queue and may not fill on a wick that touches and reverses.

For every trade in the population whose target lies within one tick of a node of weight >= 3.0,
simulate two counterfactuals from the same bar path: target **at** the node, and target at
`node - direction x max(1 tick, 0.10 x ATR_1m)`. This is a **paired** design - both arms come from the
same trade, so only discordant pairs carry information.

Report two endpoints and treat the second as the one that decides:
- `target_filled` (binary) via McNemar on discordant pairs.
- mean realized R via Wilcoxon signed-rank plus a day-block bootstrap.

Fill rate can improve while realized R gets worse - stepping in front of the level costs you the last
tick on every winner. If those two endpoints disagree, say so plainly; do not report the flattering one.

State `n_discordant` explicitly. If it is under 250 the test is underpowered and the report says so
rather than quoting a p-value as though it settled anything.

Write `research/h5_frontrun.md`.

- **done-when:** `research/h5_frontrun.md` exists and states `n_discordant`, a McNemar result for fill rate, a Wilcoxon result for realized R, and an explicit sentence on whether the two endpoints agree.

### T6 -- H3: does a veto in front of a wall pay for itself

- model: glm
- depends-on: T2

The highest-value row in the version, because it removes trades rather than adding them, and it runs
entirely on trades that already exist.

Define the veto: at entry, if the nearest node of weight >= 3.0 in the trade's direction sits closer
than 1.0R, the trade is vetoed - the best realistic outcome is under +1R against -1R of risk.

Partition the whole population into vetoed and non-vetoed. Report, for each: n, mean realized R,
median realized R, win rate, and the veto rate as a fraction of all trades. Primary endpoint is
**mean realized R** (continuous, far more powerful than win rate here), tested with a Welch t on
day-clustered means and a day-block bootstrap CI.

Then sweep the threshold at 0.8R, 1.0R, 1.2R and 1.5R and report the same table for each. If the
result only exists at one threshold it is noise; a real effect degrades smoothly.

Two ways this row can lie to itself, both of which must be checked and reported:
- If the veto fires on under 5% or over 40% of trades, the threshold is measuring something other
  than what it claims. Report the rate before the verdict.
- Vetoed trades are not a random sample - they are trades near strong levels, which may differ in
  volatility. Report ATR at entry for both groups so a confound is visible rather than hidden.

Write `research/h3_veto.md`.

- **done-when:** `research/h3_veto.md` exists, contains the four-threshold sweep table, states the veto rate at each threshold, and reports a bootstrap CI on the difference in mean realized R.

### T7 -- H9: does confluence weight track outcome at all

- model: deepseek
- depends-on: T2

The row that fits the weight vector rather than assuming it. Every weight in T2's table is currently a
guess; this measures whether the ordering is real.

For every trade in the population, compute the weight of the nearest node to the entry price at the
entry bar. Then measure the relationship between that weight and realized R: Spearman rho across all
trades, plus binned mean realized R by weight bucket as the readable artifact, plus an OLS with
day-clustered standard errors.

This uses every trade rather than a subgroup, which is why it needs roughly 780 trades rather than
several thousand. If the population is smaller than that, say so and report the achieved power.

Monotonicity is the claim being tested, not just correlation - report whether mean realized R rises
across consecutive weight buckets, and name any bucket that breaks the ordering.

Write `research/h9_confluence.md`.

- **done-when:** `research/h9_confluence.md` exists, reports a Spearman rho with a day-block bootstrap CI, and contains a binned table of mean realized R by weight bucket with an n for every bucket.

### T8 -- Instrument check: how often can 1-minute bars not tell us what happened

- model: deepseek
- depends-on: T2

Before any result above is believed, measure whether the instrument can support it.

When a trade's target and stop both lie inside a single 1-minute bar's high-low range, OHLCV cannot
say which was hit first. Count how often that happens across the population, as a percentage of all
trades and of all resolved trades.

Score the entire population twice: once assuming the stop was hit first (pessimistic - this is the
primary), once assuming the target was (optimistic). Report both headline numbers.

State plainly: if any conclusion in T5, T6 or T7 flips between the two scorings, that conclusion is a
measurement of bar resolution and not of the market. And if the ambiguous-bar rate exceeds 20%,
1-minute OHLCV is the wrong resolution for this study - which is a finding about what data to buy
next, not a reason to stop.

Write `research/h_intrabar.md`.

- **done-when:** `research/h_intrabar.md` exists, states the ambiguous-bar rate as a percentage, and reports the population's mean realized R under both the pessimistic and optimistic scorings.

### T9 -- Verdict

- model: opus
- depends-on: everything

The single judgment row. Read `research/target_autopsy.md`, `research/h5_frontrun.md`,
`research/h3_veto.md`, `research/h9_confluence.md`, `research/h_intrabar.md` and
`research/marks_audit.md`. Do not re-run any analysis and do not recompute any number - if two reports
disagree, that disagreement is itself the finding and gets reported as one.

Apply the floor stated at the top of this spec: 4 percentage points of win rate, or d = 0.15. Apply
BH-FDR at q = 0.10 across every hypothesis actually tested. Read T8 first - if the ambiguous-bar rate
is high, every other result is provisional and must be labelled so.

Answer three questions and nothing else:

1. **Does level context earn a place in OMEN?** Yes, no, or not-yet-measurable, with the specific
   number that decides it. "Not-yet-measurable" is a legitimate and expected answer given the sample
   sizes involved, and is more useful than a hedged yes.
2. **What is the one change to make next?** Exactly one, named as a file and a function.
3. **What is now settled negative?** Anything this version killed, written as a one-line tombstone
   ready to paste into the vault's settled-negatives list. If nothing was killed, say so.

Write `research/v34_verdict.md`. End it with a section headed `FOR AUSTIN` of at most ten lines,
in plain language, stating what he should do differently on the chart tomorrow - or stating that
nothing changed yet, which is an acceptable answer.

- **done-when:** `research/v34_verdict.md` exists, answers all three numbered questions under their own headings, and ends with a `FOR AUSTIN` section of ten lines or fewer.

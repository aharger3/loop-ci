# OMEN 5.1 - Honest EV, a real S rate, and true-negative labels

status: ready
version: omen-5.1
repo: aharger3/tradingbot
doc: Projects/OMEN.md

target: Replace the +0.914R headline with a number that survives a pessimistic fill model and a walk-forward split, loosen the S bar to mesh-veto-only, diagnose why the index pool fires 18 times in two years, and build the first engine-blind day deck so recall can finally be measured against days Austin actually traded.

## Why this version exists

omen-5.0 T8 produced **+0.914R per trade over 1,047 trades**. That is 4–18x above any
credible intraday edge. Three things inflate it and all three are fixable:

1. **Targets fill on intrabar touch while stops require a close.** Austin's stop rule
   is correct and is not changing — a close beyond the line is how he trades. But a bar
   that pokes the target and then closes beyond the stop currently books a **win**. That
   is a free lunch the market does not serve.
2. **In-sample.** Every rule in the engine was fitted on the same 501 days T8 scored.
3. **Unbounded runner.** Top 1% of trades carry 11% of total R. Capped at 2R the same
   run is +0.375R.

`research/t8_significance.md` also settled that **P&L can never separate S from A from C**
— 49 years of data would be needed. Tier quality has to be judged on agreement with
Austin's own grades, which requires a bigger graded corpus than 159 marks, which requires
labels on days the engine fires **nothing**. That is what the day deck is for.

## Settled in the 2026-08-12 grilling — never re-elicit

1. **Stops require a close beyond the level. Unchanged, correct, not a defect.** The
   asymmetry lives on the target side only.
2. **Target fills on intrabar touch (a resting limit does fill on touch), BUT any bar
   that touches the target and also closes beyond the stop books the LOSS.**
3. **The S bar loosens to mesh-veto-only.** The displacement gate and third-touch level
   retirement stop disqualifying S and become demotions to A.
4. **S+ is deleted.** "Earliest 3 S of the day" scored 47.6% WR against S's 57.9% over
   two years. The rank has no evidence for it and pollutes every tier comparison.
5. **Tier quality is proven by eye-match agreement, not by P&L.**
6. **The homework artifact is an engine-blind day deck** — one card per trading day,
   full 09:30–11:00 chart, no engine marks, including days the engine went silent.
   First batch: **TSLA, 60 consecutive trading days.**
7. **New rules are mined from Austin's day-deck notes only** this version. The silent-day
   grading pass, the order-block stop rule, and retiring the 84% rule are all deferred.


### T1 -- Loosen the S bar to mesh-veto-only and delete the S+ tier
- model: glm

In `signal_runner.py`, the S grade currently requires three clauses to pass: the
displacement gate, the mesh S-veto, and third-touch level retirement. The 5.0 T11
ablation measured each alone: mesh veto alone gives **24.14% S-precision at 0.18 S/day**,
all three give **25.0% at 0.07/day**. The extra 0.86 points of precision cost 2.5x the
fire rate. Loosen.

Change the S qualification so that **only the mesh S-veto can block S**. A bar that fails
the displacement gate, or that sits on a retired third-touch level, is **demoted to A** —
it must still be emitted and graded, not dropped. Keep both clauses reachable as env
flags (`S_REQUIRE_DISPLACEMENT`, `S_RETIRE_THIRD_TOUCH`, both defaulting to `0`) so the
old behaviour can still be backtested.

Delete the **S+** tier entirely. Remove the "earliest 3 S of the day" ranking, its config
constant, and every place it is emitted or reported. Anything that graded S+ now grades
plain **S**. Do not leave a deprecated alias.

Write `research/t51_s_bar.md` containing exactly these lines, filled in from a replay over
the existing mark corpus:

```
s_fires_per_day_before: 0.07
s_fires_per_day_after: <number>
s_precision_before: 25.0
s_precision_after: <number>
s_plus_references_remaining: 0
```

- **done-when:** `signal_runner.py` grades S on the mesh veto alone, demotes (never drops)
  bars failing displacement or level retirement, contains no S+ tier, and
  `research/t51_s_bar.md` reports an after-rate above 0.15/day.
- **verify:**
  ```bash
  test -s research/t51_s_bar.md
  grep -q '^s_plus_references_remaining: 0$' research/t51_s_bar.md
  python -c "import re,sys; t=open('research/t51_s_bar.md').read(); v=float(re.search(r'^s_fires_per_day_after: ([0-9.]+)',t,re.M).group(1)); sys.exit(0 if v>0.15 else 1)"
  python -c "import sys,subprocess; r=subprocess.run(['grep','-rn','S+','signal_runner.py','universe.py'],capture_output=True,text=True); sys.exit(1 if r.stdout.strip() else 0)"
  python -c "import signal_runner"
  ```


### T2 -- Pessimistic target fill: a bar that touches target and closes beyond stop is a LOSS
- model: opus

This is the edge-deciding row. Read it twice before changing anything.

In `backtest_week.py` the exit logic currently resolves a bar by checking the target
first. Austin's real rules are asymmetric **by design and correctly so**:

- **Stop:** requires the candle to **close** beyond the stop level (`STOP_ON_CLOSE=1`,
  already shipped in 5.0 T4). Do not change this. It is right.
- **Target:** a resting limit order, so it fills on **intrabar touch**. Also right.

The defect is what happens when **one bar does both**. Today the target wins and the
trade books a full winner. In reality you cannot know, from a 1-minute bar, whether price
tagged the target before or after it collapsed through the stop — and assuming it always
tagged first is the single most optimistic assumption in the whole backtest.

New rule, behind `PESSIMISTIC_FILL` (default `1`): **if a bar's high/low touches the
target AND that same bar's close is beyond the stop level, the trade books a LOSS at the
stop.** This applies at every rung of ladder B, including the scale-out at 1R and the
runner's exit. If the scale-out rung and the stop collide on the same bar, the whole
position books the loss — no partial credit.

Keep `PESSIMISTIC_FILL=0` reproducing today's behaviour exactly, so both arms backtest.

Then re-run the two-year backtest (`research/t8_two_year.py`, same 501-day window, same
29 symbols, same $1,000 risk) under both settings and write:

- `research/t51_fill_flip.jsonl` — one row per trade whose outcome **changed**, with
  keys `symbol`, `date`, `entry_i`, `flip_bar_i`, `old_outcome`, `new_outcome`, `old_r`,
  `new_r`, `stop`, `target`, and the flip bar's `open`/`high`/`low`/`close`.
- `research/t51_fill.md` with exactly these lines:

```
trades_total: <n>
trades_flipped: <n>
win_rate_optimistic: <pct>
win_rate_pessimistic: <pct>
ev_optimistic: <R>
ev_pessimistic: <R>
```

- **done-when:** `PESSIMISTIC_FILL` defaults on, same-bar touch-and-close-beyond books the
  loss at every ladder rung, both arms run, and the flip list is non-empty with a
  pessimistic win rate no higher than the optimistic one.
- **verify:**
  ```bash
  test -s research/t51_fill.md
  test -s research/t51_fill_flip.jsonl
  python -c "import json,sys; rows=[json.loads(l) for l in open('research/t51_fill_flip.jsonl')]; sys.exit(0 if rows and all(set(('symbol','date','entry_i','flip_bar_i','old_outcome','new_outcome','old_r','new_r','stop','target'))<=set(r) for r in rows) else 1)"
  python -c "import re,sys; t=open('research/t51_fill.md').read(); g=lambda k: float(re.search(r'^%s: ([-0-9.]+)'%k,t,re.M).group(1)); sys.exit(0 if g('win_rate_pessimistic')<=g('win_rate_optimistic') and g('trades_flipped')>0 else 1)"
  ```


### T3 -- Card deck of every flipped trade, so Austin can see the fill rule with his own eyes
- model: deepseek
- depends-on: T2

Austin asked to verify the target-fill mechanics visually before trusting the number.
Build an HTML card deck from `research/t51_fill_flip.jsonl` — the same self-contained
single-file format as `omen-5.0-br-cards.html`, no external CDN, opens by double-click.

**One card per flipped trade.** Each card shows the 09:30–11:00 1-minute candle chart for
that symbol-day with:

- horizontal lines for **entry**, **stop**, and **target**, each labelled with its price
- the **entry bar** outlined
- the **flip bar** highlighted in a distinct colour, with a caption directly under the
  chart reading: `This bar touched the target at <target> AND closed at <close>, beyond
  the stop at <stop>. Old model: WIN <old_r>R. New model: LOSS <new_r>R.`

Sort cards by `abs(old_r - new_r)` descending so the most consequential flips are first.
Header of the deck states the totals from `research/t51_fill.md`.

Write the file to `research/omen-5.1-fill-cards.html`.

- **done-when:** the deck exists, has one card per row in the flip jsonl, is fully
  self-contained (no `http://` or `https://` asset references), and every card names its
  flip bar's close and the stop price.
- **verify:**
  ```bash
  test -s research/omen-5.1-fill-cards.html
  python -c 'import sys; n=sum(1 for _ in open("research/t51_fill_flip.jsonl")); h=open("research/omen-5.1-fill-cards.html").read(); sys.exit(0 if h.count("class=\"card\"")==n else 1)'
  python -c 'import sys,re; h=open("research/omen-5.1-fill-cards.html").read(); sys.exit(1 if re.search(r"(src|href)=.?https?://",h) else 0)'
  ```


### T4 -- The honest EV table: pessimistic fill, R-capped, walk-forward out-of-sample
- model: opus
- depends-on: T2

`research/t8_ev.md`'s +0.914R is in-sample, optimistically filled, and uncapped. Produce
the number that replaces it as OMEN's official expectancy.

Split the 501-day window **chronologically**: the first **75%** of trading days are
in-sample, the final **25%** are out-of-sample. Never shuffle — a random split leaks the
future into the past. The rules were fitted on the whole history, so the out-of-sample
number is not a true holdout either; **say so explicitly in the report** rather than
overselling it. It is the best available check, not proof.

Run the two-year backtest at the T1 + T2 defaults and report a table with one row per
combination of: fill model (optimistic / pessimistic) × R cap (uncapped / capped at 2R) ×
sample (in / out). For each cell report trades, win rate, EV/trade in R, and a
bootstrap 95% CI (20,000 resamples, seeded — reuse the method in
`research/t8_significance.md`).

Then state, in plain English a non-quant can read, which single cell Austin should treat
as the truth and why. The recommended answer is **pessimistic fill, capped at 2R,
out-of-sample** — every optimistic assumption removed at once. If that cell is still
positive, the edge survives its own worst case.

Write `research/t51_ev_honest.md` ending with exactly these lines:

```
headline_ev_r: <R>
headline_ev_ci_low: <R>
headline_ev_ci_high: <R>
headline_win_rate: <pct>
headline_trades: <n>
headline_cell: pessimistic_fill/cap_2r/out_of_sample
edge_survives: <yes|no>
```

Set `edge_survives: yes` only if `headline_ev_ci_low` is above zero.

- **done-when:** the full 8-cell table exists with CIs, the plain-English verdict names
  one cell, and the trailer lines are present and internally consistent.
- **verify:**
  ```bash
  test -s research/t51_ev_honest.md
  grep -q '^headline_cell: pessimistic_fill/cap_2r/out_of_sample$' research/t51_ev_honest.md
  python -c "import re,sys; t=open('research/t51_ev_honest.md').read(); g=lambda k: re.search(r'^%s: (\\S+)'%k,t,re.M).group(1); lo=float(g('headline_ev_ci_low')); hi=float(g('headline_ev_ci_high')); ev=float(g('headline_ev_r')); sv=g('edge_survives'); sys.exit(0 if lo<=ev<=hi and int(g('headline_trades'))>0 and sv==('yes' if lo>0 else 'no') else 1)"
  ```


### T5 -- Why the index pool fires 18 times in two years
- model: glm

`INDEX_POOL` (QQQ/SPY/IWM) produced **18 trades in 501 trading days** while MAJOR_15
produced 605. Austin considers indices and ETFs his fastest route to profitability, so a
structurally blind engine there is the most expensive open defect in the project. Find
the cause. **Diagnose only — do not add levels, loosen gates, or change any default.**

Instrument a replay over all 501 days for QQQ, SPY and IWM and write a funnel that starts
from every day and narrows to every fired trade. Report, per symbol and pooled:

- days with **any** candidate level detected at all, and the mean level count per day
- of those, days where a break-and-retest or order-block **setup** formed
- of those, days a signal was **generated**
- of those, days a signal **survived** each gate in turn — session window, mesh veto,
  displacement, level retirement, no-repeat, `_SKIP_GRADES`
- the **single gate that kills the most index days**, named outright

Also report the same funnel for TSLA as a control, so the index numbers can be read
against a symbol the engine handles well. If the loss is upstream of the gates — i.e. the
levels themselves are never detected on indices — say that plainly, because it means the
fix is new level geometry (overnight high/low, VWAP, prior-day value area, opening range)
rather than gate tuning, and that is a 5.2 build.

Write `research/t51_index_funnel.md` ending with exactly these lines:

```
index_days_with_levels: <n>/1503
index_days_with_setup: <n>
index_days_with_signal: <n>
index_days_traded: <n>
top_killer_gate: <name>
loss_is_upstream_of_gates: <yes|no>
```

- **done-when:** the per-symbol funnel exists with the TSLA control, and the trailer names
  one gate and states whether the loss is upstream. No engine default changed.
- **verify:**
  ```bash
  test -s research/t51_index_funnel.md
  grep -qE '^top_killer_gate: \\S+' research/t51_index_funnel.md
  grep -qE '^loss_is_upstream_of_gates: (yes|no)$' research/t51_index_funnel.md
  grep -q 'TSLA' research/t51_index_funnel.md
  git diff --exit-code signal_runner.py universe.py backtest_week.py
  ```


### T6 -- The engine-blind TSLA day deck: 60 consecutive days, no engine marks
- model: deepseek

Every card deck so far has been **one card per engine fire**, which can only measure
precision. Recall is the gate, and recall needs labels on days the engine fires
**nothing**. Austin's own estimate is that roughly **60% of TSLA days contain an S
trade**; the engine finds S on a handful. This deck tests that directly.

Build `research/omen-5.1-tsla-day-deck.html` from `data_archive/` — **one card per
trading day**, the **60 most recent consecutive TSLA trading days** in the archive, with
no days skipped for any reason. Same self-contained single-file HTML format as the
existing decks.

Each card shows the **full 09:30–11:00 1-minute candle chart** for that day and nothing
else that could bias the read:

- **No engine marks. No entries, no signals, no tiers, no levels, no shading.** A card
  must be indistinguishable whether the engine fired 3 signals or zero that day. This is
  the whole point of the deck; an overlay anywhere invalidates the batch.
- Prior-day high/low **may** be drawn, since Austin reads those off the chart himself —
  but nothing the engine computed.
- A card id of the form `TSLA_<YYYY-MM-DD>`, a free-text notes box, and a grade selector
  offering **S / A / C / none**, where **`none` means "no tradeable setup on this day"**
  and is a first-class answer, not a skip.

The deck must export grades as JSONL to the clipboard or a download, one row per card with
`card_id`, `symbol`, `date`, `grade`, `entry_i` (minutes from 09:30, blank if `none`), and
`notes`. Also write `research/t51_day_deck_manifest.jsonl` — one row per card with
`card_id`, `date`, and `engine_fires_that_day` (the count the engine actually produced).
**The manifest is for scoring after Austin grades, and its contents must not appear
anywhere in the HTML.**

- **done-when:** the deck has exactly 60 day cards, contains no engine-derived overlay,
  offers `none` as a grade, and the manifest has 60 rows carrying the engine fire counts.
- **verify:**
  ```bash
  test -s research/omen-5.1-tsla-day-deck.html
  python -c 'import sys; h=open("research/omen-5.1-tsla-day-deck.html").read(); sys.exit(0 if h.count("class=\"card\"")==60 else 1)'
  python -c 'import sys; h=open("research/omen-5.1-tsla-day-deck.html").read(); sys.exit(0 if "none" in h and "austin_tier" not in h and "engine_fires" not in h else 1)'
  python -c "import json,sys; r=[json.loads(l) for l in open('research/t51_day_deck_manifest.jsonl')]; sys.exit(0 if len(r)==60 and all('engine_fires_that_day' in x for x in r) else 1)"
  ```


### T7 -- Eye-match agreement scorer: the metric that replaces P&L for judging tiers
- model: glm
- depends-on: T1

`research/t8_significance.md` proved P&L cannot separate the tiers — the smallest gap the
sample could detect is larger than every observed gap, and closing that would take
decades. Tier quality must instead be scored as **agreement with Austin's grade on the
same bar**. Build that scorer now so it is ready the moment the day deck comes back.

Write `research/t51_eye_match.py`, taking a marks file (default
`research/austin_marks_v7.jsonl`) and producing `research/t51_eye_match.md`. For every
mark where the engine also produced a signal within **±2 bars** of the marked entry,
compare the engine's `austin_tier` to Austin's grade and report:

- a full **confusion matrix**, Austin's grade (S/A/C/X) × engine's tier (S/A/C/X/no-fire)
- **exact agreement rate** overall and per Austin-grade
- **adjacent agreement** (off by one tier) as a separate number
- the two directional error rates named plainly: **over-grading** (engine says S, Austin
  says C or X) and **under-grading** (Austin says S, engine says C, X, or did not fire)
- a **Cohen's kappa**, so agreement is reported against chance rather than raw

Treat "engine did not fire" as its own column, never as a missing value — a silent engine
on an S bar is the exact failure this project exists to fix, and dropping those rows would
hide it.

The script must accept `--marks <path>` so the same scorer runs on the graded day deck
later with no edits. End `research/t51_eye_match.md` with exactly these lines:

```
marks_scored: <n>
exact_agreement: <pct>
kappa: <float>
over_grade_rate: <pct>
under_grade_rate: <pct>
s_recall: <n>/<n>
```

- **done-when:** the scorer runs on v7 marks, emits the confusion matrix with a no-fire
  column and a kappa, accepts `--marks`, and the trailer lines are present.
- **verify:**
  ```bash
  test -s research/t51_eye_match.md
  python research/t51_eye_match.py --marks research/austin_marks_v7.jsonl
  grep -qE '^kappa: [-0-9.]+$' research/t51_eye_match.md
  grep -qE '^s_recall: [0-9]+/[0-9]+$' research/t51_eye_match.md
  grep -q 'no-fire' research/t51_eye_match.md
  ```


### T8 -- The 5.1 verdict
- model: deepseek
- depends-on: everything

Write `research/v51_verdict.md`. No new analysis, no new numbers — read the artifacts the
other rows produced and state what is now true, in plain English Austin can read in three
minutes.

Cover, in this order:

1. **The honest EV** from `research/t51_ev_honest.md`, stated against the old +0.914R, and
   whether the edge survived its own worst case.
2. **What the fill fix cost**, from `research/t51_fill.md` — trades flipped and the win
   rate delta. Name the pessimistic win rate against Austin's 55% gate outright.
3. **The new S rate and precision** from `research/t51_s_bar.md`, against his 1–3/day
   expectation, and how far short it still is.
4. **Why the index pool is silent**, from `research/t51_index_funnel.md`, and whether the
   fix is gate tuning or new level geometry.
5. **The eye-match baseline** from `research/t51_eye_match.md` — the agreement number the
   graded day deck will be scored against.
6. **What Austin has to do next**, as a single named action.

End the file with exactly these lines:

```
verdict_ev_r: <R from t51_ev_honest.md headline_ev_r>
verdict_win_rate: <pct>
verdict_s_per_day: <n>
verdict_edge_survives: <yes|no>
verdict_next_action: <one sentence>
```

- **done-when:** `research/v51_verdict.md` exists, cites all five upstream artifacts by
  filename, and its trailer numbers match the source files exactly.
- **verify:**
  ```bash
  test -s research/v51_verdict.md
  for f in t51_ev_honest.md t51_fill.md t51_s_bar.md t51_index_funnel.md t51_eye_match.md; do grep -q "$f" research/v51_verdict.md || exit 1; done
  python -c "import re,sys; v=open('research/v51_verdict.md').read(); e=open('research/t51_ev_honest.md').read(); a=re.search(r'^verdict_ev_r: (\\S+)',v,re.M).group(1); b=re.search(r'^headline_ev_r: (\\S+)',e,re.M).group(1); sys.exit(0 if a==b else 1)"
  grep -qE '^verdict_next_action: .+' research/v51_verdict.md
  ```

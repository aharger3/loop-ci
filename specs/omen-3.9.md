# OMEN 3.9 - teach the engine the letter S

status: ready
version: omen-3.9
repo: aharger3/tradingbot
doc: Projects/OMEN.md

target: make Austin's own tier (S/A/C/X) a value the code computes on every signal, fix the miss
taxonomy that hides the One Candle Rule, code the timing/re-entry rules he settled on, and
measure S-only against today's trading set — without changing what the bot actually takes.

**Read this framing once; no row re-derives it.**

omen-3.8 landed in full (PR #17, gate exit 0, `research/v38_verdict.md`). Where that left things:
S-grade **fired** recall **10/77 = 13.0%** (flat vs the T0 baseline), S any-signal **28/77 =
36.4%**, precision **25/66 = 37.9%**. 3.8's T4 instrumented `detect_break_retest`'s ordered FSM
across all 27 `no_break_retest` S misses and **exonerated the geometry** — they are true
negatives: `seek_retest` 17 (broke, cleared, price never returned), `seek_leave` 6 (chop on the
level, rejected by design), `seek_break` 6 (break pre-dated the window), 1 stale confirm. **Do
not re-open `detect_break_retest`'s geometry or tolerances in this spec, and do not arm
`DETECT_WIDE`** — `research/t5_wide_probe.py` already proved widening recovers zero distinct S
marks after dedup while halving precision 38.5% -> 19.4%.

Two structural defects, found while planning 3.9, are what this version fixes:

**(a) The miss taxonomy short-circuits.** `research/miss_autopsy.py`'s `classify_no_detection`
returns `"no_break_retest"` the moment `detect_break_retest` is falsy for every level — **before
`detect_order_block_setup` is ever called** (the `if not br_any: return` at ~line 120). The One
Candle Rule is therefore invisible in the entire miss vocabulary, and not one of the 27 marks
was ever tested for it. The label is wrong; the real setup on those bars is unknown.

**(b) There is no S in the engine.** `signal_runner.py` (~line 659) sets
`sig.setdefault("austin_tier", None)` and the comment says plainly "ALWAYS None — no mapping from
A+/A/B/C exists and none is asserted here." Engine grades (A+/A/B/C/X) and Austin's tiers
(S/A/C/X) are two different scales that have never been joined, so "S-grade fired recall" has
never been a quantity the code could compute.

**Austin's settled rulings, 2026-08-09 (authoritative; contradict none of them):**

1. **The 84% rule is a re-entry ONLY — it never fires standalone.** It arms only after a *loser*
   from break-and-retest, the one candle rule, or both. Trigger: a candle closes at or above the
   price originally entered -> take it, keep the original stop unless a new level or pivot
   structure makes more sense. The predicament is *correct thesis, wrong stop*.
   `Trading-Bot-Rulesets.md` Setup 2 and Setup 4 describe "entry on the break of the opening
   range" — **that is wrong** and T6 corrects it. The code's `RuleOf84Detector` is right.
2. **Grades are S / A / C / X and only S is tradeable.** A = one or two clauses missing, valid
   under the right higher-timeframe circumstance. C = fits one of the three setups but is
   in-between mesh or targets HOD/LOD. A and C are logged for backtest data and may become
   tradeable later. X is not a signal class at all — it is Austin's "don't trade this" marker.
3. **Fill veto is bar-relative, not session-relative — and it must not require the candle to
   close.** No S when the entry price sits in the top 25% of the signal bar's range-so-far (long)
   or the bottom 25% (short). **Exempt: the 84% re-entry**, where the close-through *is* the
   signal. Austin, 2026-08-09: *"I don't want to wait for the candle to close for an entry,
   because sometimes the one you enter on closes really far and I don't want to potentially miss
   an entry. The 25 percent rule is fine — it just helps the fact of not entering right at low of
   day."* So the veto is a **fill-quality guard, not a confirmation gate**: it is evaluated
   against the bar as formed at the moment of entry, and it may never be implemented in a way
   that defers an entry to the next bar.
4. **HTF opposition is not settled — measure both arms, decide nothing.** Austin, 2026-08-09:
   *"HTF note not important, I imagine it changes risk if we get good backtest results, or a level
   above S that you don't even look for perfect strategies for entry."* `vetoed_htf` is 8 of the
   40 S-miss cards and three of his notes grade the mark S *"if you get a good fill not at high of
   day"*. So clause 4 of the S definition ships as a **parameter, not a constant**, and T8 reports
   both arms side by side.
5. **No repeat entries; scope is symbol + direction + level.** A different level or the other
   direction is a different idea and may fire. Only an armed 84% re-entry may be the second.
6. **Compute S, do not gate on it.** Nothing in this spec may change which signals the engine
   trades. Every new rule is computed into `austin_tier` and/or sits behind a default-OFF flag.
   `research/regression_gate.py` against `research/baseline_3.8.json` must exit 0 on every row —
   it already passes on main, so any failure is this spec's fault.

**Austin-supplied inputs, if present.** Two files may be added to `research/` by Austin before
this runs: `research/priority_pool.json` (the 14 equity tickers) and
`research/austin_homework_39.md` (re-grades of 29 marks). Rows that use them must degrade
gracefully and say so in their output if a file is absent — **no row may fail because Austin's
file is missing.**


### T1 -- stop the miss taxonomy short-circuiting past the One Candle Rule
- model: glm
- depends-on: (none)

In `research/miss_autopsy.py`, `classify_no_detection` currently does:

    if not br_any:
        return "no_break_retest", "..."

and only reaches `detect_order_block_setup` afterwards. That ordering means a bar where
break-and-retest fails is labelled `no_break_retest` and **the order block is never tested** —
so the One Candle Rule (which IS `detect_order_block_setup` alone, per `omen_bot.py`'s
`SignalType.ONE_CANDLE_RULE` comment) cannot appear in the taxonomy at all.

Restructure so both setups are evaluated before a label is chosen. Keep the existing reason
strings; add exactly one new reason, `no_setup_any`, to `REASONS`/`REASON_SET`. New semantics:

- B&R falsy **and** both order-block sides `None` -> `no_setup_any` (nothing the engine knows
  how to trade exists on this bar).
- B&R falsy **but** an order block exists -> `no_break_retest`, and the `detail` string must
  begin with `OB present:` naming which side (bullish/bearish) — these are the candidate One
  Candle Rule entries.
- B&R truthy and both OB sides `None` -> `no_order_block`, unchanged.
- The existing residual case (both present, neither built a signal) stays as it is.

Do not change `detect_break_retest`, `detect_order_block_setup`, or any engine code — this row
touches `research/miss_autopsy.py` only. Then re-run it over the 159 marks
(`python research/miss_autopsy.py`) and write `research/t1_taxonomy_rerun.md` with the new
reason x tier table plus, on its own line and in exactly this form (the runner greps for it):

    no_break_retest_S: 27 -> <after>
    ob_present_S: <count of S marks now labelled no_break_retest with an OB present>

Also state in prose how many of 3.8's 17 `seek_retest`, 6 `seek_leave` and 6 `seek_break` marks
now show `OB present:` — that is the number [[omen-3.9-homework]] is asking Austin to confirm
by eye, and T8 cites it.

- **done-when:** `research/miss_autopsy.py` evaluates the order block before assigning
  `no_break_retest`; `research/miss_autopsy.md` regenerates without error; `research/t1_taxonomy_rerun.md`
  carries both grep lines, and `no_break_retest_S`'s after-number is <= 27.
- **verify:**
  ```bash
  python research/miss_autopsy.py
  python -c "import re,sys; t=open('research/t1_taxonomy_rerun.md').read(); m=re.search(r'no_break_retest_S:\s*(\d+)\s*->\s*(\d+)',t); o=re.search(r'ob_present_S:\s*(\d+)',t); sys.exit(0 if m and o and int(m.group(2))<=int(m.group(1)) else 1)"
  python research/regression_gate.py
  ```


### T2 -- add the `timing_miss` reason: the engine took a later, worse bar
- model: glm
- depends-on: T1

`research/mark_batch_02_grades.jsonl` (60 cards Austin graded 2026-08-09) carries free-text notes
that name a miss the taxonomy has no word for. Six of them say the same thing: *"4 candles
earlier is entry"*, *"entry 5 candles earlier but not at high of day"*, *"you missed the entry 9
candles earlier perfect break and retest one candle rule hammer stick"*, *"1 candle earlier
entry"*. Setup and level were right; **the bar chosen was wrong** — a qualifying entry existed
several bars earlier and the engine passed it over for a later, worse one. That is distinct from
`fired_wrong_bar`, which only means "fired on this symbol-day but >2 bars away" with no claim
about which bar was better.

Add `timing_miss` to `REASONS`/`REASON_SET` in `research/miss_autopsy.py` and classify it: for a
mark where the engine fired on that symbol-day but outside the +/-2 tolerance, replay the bars
between the mark and the engine's entry and check whether **any earlier bar than the engine's
would itself have produced a signal** (call the engine's own `detect_break_retest` /
`detect_order_block_setup` helpers exactly as `classify_no_detection` already does — do not
reimplement detection). If yes -> `timing_miss` with a detail naming the earlier bar index and
how many bars early. If no -> `fired_wrong_bar`, unchanged. `timing_miss` must be checked before
`fired_wrong_bar` so it takes precedence.

Re-run and write `research/t2_timing_miss.md` with the count and, on its own line:

    timing_miss_S: <count of S marks reclassified from fired_wrong_bar to timing_miss>

The number must be >= 1 — `research/mark_batch_02_grades.jsonl` contains at least five S cards
with explicit "N candles earlier" notes, so a zero here means the classifier is not firing and
the row is wrong, not the data.

- **done-when:** `timing_miss` is in `REASON_SET`, `research/miss_autopsy.py` runs clean, and
  `research/t2_timing_miss.md` states a `timing_miss_S:` count of at least 1.
- **verify:**
  ```bash
  python -c "import sys; sys.path.insert(0,'research'); import miss_autopsy; sys.exit(0 if 'timing_miss' in miss_autopsy.REASON_SET else 1)"
  python research/miss_autopsy.py
  python -c "import re,sys; m=re.search(r'timing_miss_S:\s*(\d+)', open('research/t2_timing_miss.md').read()); sys.exit(0 if m and int(m.group(1))>=1 else 1)"
  python research/regression_gate.py
  ```


### T3 -- merge mark_batch_02 into a v3 mark corpus (159 -> 184)
- model: deepseek
- depends-on: (none)

`research/mark_batch_02_grades.jsonl` holds 60 blind gradings (35 S / 11 A / 14 X) written
2026-08-09 in commit `ecab6b7`. **25 of its 60 `(symbol, day, entry_i)` keys are not in
`research/austin_marks_v2.jsonl`** — they are new labelled bars that no recall number has ever
counted. The other 35 overlap and must not be duplicated.

Write `research/build_marks_v3.py` and run it to produce `research/austin_marks_v3.jsonl`:

- Start from all 159 rows of `austin_marks_v2.jsonl`, schema unchanged.
- For each batch_02 row, key on `(symbol, day, entry_i)`. If the key is new, append a row in the
  v2 schema with `tier` = the card's `austin_grade`. If it already exists and `austin_grade`
  disagrees with the existing `tier`, **the newer grading wins** — overwrite, and log every such
  overwrite.
- Carry `note` and `kind` through as extra fields where present; they are Austin's own words and
  T4/T8 read them.
- If `research/austin_homework_39.md` exists, additionally apply any line matching
  `**SYMBOL** YYYY-MM-DD ... setup: <X> · still S? <Y>` — set `austin_setup` to X and, when Y is
  a clear no, downgrade `tier`. **If the file does not exist, skip this step silently and say so
  in the report** — the row must still pass.

Write `research/t3_marks_v3.md` with the before/after counts and per-tier breakdown, including
on its own line:

    marks_v3_total: 159 -> <after>

Do **not** repoint `t4_engine_recall.py`, `miss_autopsy.py`, `regression_gate.py` or
`baseline_3.8.json` at v3 in this row — the regression gate is locked to the v2 mark set and
must stay comparable. T8 reports v3 numbers separately.

- **done-when:** `research/austin_marks_v3.jsonl` exists with at least 184 rows, no duplicate
  `(symbol, day, entry_i)` keys, and `research/t3_marks_v3.md` carries the `marks_v3_total:` line.
- **verify:**
  ```bash
  python -c "import json,sys; rows=[json.loads(l) for l in open('research/austin_marks_v3.jsonl')]; k=[(r['symbol'],r['day'],r['entry_i']) for r in rows]; sys.exit(0 if len(rows)>=184 and len(k)==len(set(k)) else 1)"
  python -c "import re,sys; m=re.search(r'marks_v3_total:\s*159\s*->\s*(\d+)', open('research/t3_marks_v3.md').read()); sys.exit(0 if m and int(m.group(1))>=184 else 1)"
  ```


### T4 -- make `austin_tier` a computed value: S / A / C / X
- model: opus
- depends-on: (none)

This is the row the whole version exists for. `signal_runner.py` currently does
`sig.setdefault("austin_tier", None)` with a comment stating it is always None because no mapping
from A+/A/B/C exists. Replace that with a real computation. **This must not change
`sig["grade"]`, `_SKIP_GRADES`, or which signals `_route` accepts** — `austin_tier` is a new
reported field and nothing branches on it in this version.

Write the rule into `Trading-Bot-Rulesets.md` first, as a new top-level section
`## Austin's Tiers (S / A / C / X)`, in the prose style of the existing setup sections. It states
exactly this, which Austin settled on 2026-08-09:

> **S — tradeable.** All four hold: (1) the setup is one of exactly three — break-and-retest, the
> one candle rule (order block), or an **armed** 84% re-entry; nothing else is ever S. (2) the
> entry close does not sit in the top 25% of the signal bar's own range (long) or the bottom 25%
> (short), measured against the bar **as formed at the moment of entry** — this is a fill-quality
> guard, never a wait-for-the-close confirmation gate — *exempt: the 84% re-entry, where the
> close-through is the signal*. (3) no prior S has
> fired today on the same **symbol + direction + level** — *exempt: an armed 84% re-entry, which
> is allowed to be the second*. (4) the higher-timeframe bias does not oppose the direction —
> **unless clause 2 passes**, in which case a good fill may carry an opposing HTF. Clause 4 is
> the one clause Austin has not settled; it is a switch, and both arms are measured before
> anyone picks.
> **A** — one or two clauses missing, valid under the right higher-timeframe circumstance.
> Detected and logged, **not traded**. **C** — fits one of the three setups but is in-between
> mesh, or targets HOD/LOD. Detected and logged, **not traded**. **X** — not a level worth
> tracking; Austin's own "do not trade" marker, not a signal class the engine emits.

Then implement it in `signal_runner.py` as a module-level function
`compute_austin_tier(sig, candles, fired_ideas, htf_bias) -> str` returning `"S"`, `"A"` or
`"C"`, called from `_route` so every signal — accepted or skipped — carries
`sig["austin_tier"]`. Three named helpers, each doing one clause, so T5/T8 can cite them:

- `bar_extreme_veto(sig, candle) -> bool` — clause 2. True when vetoed. Compares the signal's
  entry price against the bar's own high/low as of entry — it must not reference a later bar or a
  confirmed close. Returns False unconditionally for `SignalType.REENTRY_84_RULE`.
- `idea_key(sig) -> tuple` — clause 3's identity: `(symbol, direction, level_name)`. The level
  name is the reference level the signal was built against (`OR high`/`OR low`/`PDH`/`PDL`/
  `PMH`/`PML`), not the price.
- `setup_is_s_eligible(sig) -> bool` — clause 1. True only for `BREAK_AND_RETEST`,
  `ONE_CANDLE_RULE`, `REENTRY_84_RULE`. `FAIR_VALUE_GAP` and `FLAG` are never S.

Tiering: all four clauses -> `S`. Clause 1 holds but one or two of clauses 2/3/4 fail -> `A`.
Clause 1 holds and three or more fail, or the signal targets the session HOD/LOD -> `C`. Clause 1
fails -> `C`. The function never returns `"X"`; X is Austin's marking vocabulary, not an engine
output, and the section above says so.

Clause 4 is a parameter, not a constant: add `HTF_OPPOSITION_VETO = "hard"` at module level,
accepting `"hard"` (opposed HTF -> never S) or `"fill_override"` (a signal passing clause 2 may
still be S with an opposing HTF). `compute_austin_tier` reads it; T8 measures both. Default
`"hard"` because that is today's behaviour.

Add `AUSTIN_TIER_ENABLED = True` at module level (this row is additive and cannot change routing,
so it ships ON) and `TRADE_S_ONLY = False` — the switch that would restrict `_route` to S. **It
must be read nowhere in this version**; it exists so T8 can A/B it and Austin can arm it later.

- **done-when:** `Trading-Bot-Rulesets.md` has an `## Austin's Tiers` section naming all four
  clauses; `signal_runner.compute_austin_tier`, `bar_extreme_veto`, `idea_key` and
  `setup_is_s_eligible` all exist; `TRADE_S_ONLY` is False; and `research/regression_gate.py`
  exits 0 — proving routing is byte-identical.
- **verify:**
  ```bash
  python -c "import signal_runner as s,sys; sys.exit(0 if all(hasattr(s,n) for n in ('compute_austin_tier','bar_extreme_veto','idea_key','setup_is_s_eligible')) and s.TRADE_S_ONLY is False and s.HTF_OPPOSITION_VETO=='hard' else 1)"
  grep -q "Austin's Tiers" Trading-Bot-Rulesets.md
  python research/regression_gate.py
  ```


### T5 -- enforce no-repeat entries behind a flag, and prove the idea key works
- model: glm
- depends-on: T4

T4 built `idea_key(sig)` and used it inside the tier computation. This row makes it an actual
routing rule — **default OFF**, so the engine's behaviour is unchanged and the gate still passes.

In `signal_runner.py` add `ENFORCE_NO_REPEAT = False` at module level next to the other flags. The
runner keeps a per-session `self._fired_ideas` set of `idea_key(sig)` values for every signal it
accepts. When `ENFORCE_NO_REPEAT` is True and a new signal's `idea_key` is already in that set,
the signal is skipped with `sig["reason"] += " [skip: repeat idea]"` — **unless** its type is
`SignalType.REENTRY_84_RULE`, which is always allowed through, since the 84% re-entry is by
definition the second bite at the same idea. When the flag is False the set is still maintained
(so the tier computation and the report have the data) but nothing is skipped.

Then measure it without arming it: write `research/t5_no_repeat_effect.py`, which replays the
159 v2 marks with the flag forced True in-process and reports how many engine entries would be
suppressed and whether any *baseline-fired mark* would have gone silent. Write
`research/t5_no_repeat.md` with prose plus, on its own line:

    repeat_entries_suppressed: <n>
    baseline_marks_lost: <n>

`baseline_marks_lost` is the number that decides whether Austin can arm this — say plainly in
the prose whether it is safe to flip.

- **done-when:** `ENFORCE_NO_REPEAT` exists and is False; `research/t5_no_repeat.md` carries both
  grep lines; `research/regression_gate.py` exits 0 (the flag is OFF, so it must be a no-op).
- **verify:**
  ```bash
  python -c "import signal_runner as s,sys; sys.exit(0 if s.ENFORCE_NO_REPEAT is False else 1)"
  python research/t5_no_repeat_effect.py
  python -c "import re,sys; t=open('research/t5_no_repeat.md').read(); sys.exit(0 if re.search(r'repeat_entries_suppressed:\s*\d+',t) and re.search(r'baseline_marks_lost:\s*\d+',t) else 1)"
  python research/regression_gate.py
  ```


### T6 -- widen 84% arming to one-candle-rule losers, and correct the rulebook
- model: glm
- depends-on: (none)

Two related defects, both settled by Austin 2026-08-09.

**Code.** `signal_runner.py` has `RULE84_ARM_BNR_ONLY = True` — the 84% re-entry arms only after a
break-and-retest loser, so a stopped-out **one candle rule** trade never arms it. Austin's rule:
it arms after a loser from break-and-retest, the one candle rule, **or both**. Replace the boolean
with `RULE84_ARM_ON = frozenset({SignalType.BREAK_AND_RETEST, SignalType.ONE_CANDLE_RULE})` and
gate arming on the stopped trade's type being in that set. Keep `RULE84_ARM_BNR_ONLY` as a
module-level alias computed from the new set (`RULE84_ARM_BNR_ONLY = RULE84_ARM_ON == frozenset({SignalType.BREAK_AND_RETEST})`)
so nothing that reads the old name breaks. FVG and flag losers must **not** arm it.

**Doc.** `Trading-Bot-Rulesets.md` Setup 2 ("5-Minute Opening Range (84% Rule Related)") and Setup
4 ("84% Rule (Full Details)") both describe the 84% rule as a **standalone entry on the break of
the opening range** — line 47: *"Once broken, price tends to not return, so entry on break is high
probability."* **That is wrong and it is the doc-vs-code conflict that has been open since
2026-08-07.** Austin's ruling: *the 84% rule can never happen by itself; it is only taken after a
loser from B&R, the one candle rule, or both. When a candle closes at or above the same price
where you originally entered, take the trade and leave the stop where it was, or where it makes
the most sense (a new level, pivot structure) — because the predicament is correct thesis, wrong
stop.* Rewrite both sections to say that, and add a line to each beginning
`**VOID (2026-08-09):**` naming what the old text claimed and why it was wrong, so the dead
version cannot be resurrected from git history.

Because arming widens, this can add entries — run the gate and confirm it still exits 0 (the gate
fails only on *lost* fires, so additions are fine). Write `research/t6_rule84_arming.md` with the
before/after count of armed re-entries over the 159 marks, on its own line:

    armed_84_entries: <before> -> <after>

- **done-when:** `RULE84_ARM_ON` exists as a frozenset containing both setup types; both rulebook
  sections carry a `**VOID (2026-08-09):**` line; `research/t6_rule84_arming.md` carries the
  grep line; the gate exits 0.
- **verify:**
  ```bash
  python -c "import signal_runner as s, omen_bot as o, sys; a=getattr(s,'RULE84_ARM_ON',None); sys.exit(0 if a and {o.SignalType.BREAK_AND_RETEST,o.SignalType.ONE_CANDLE_RULE} <= set(a) and o.SignalType.FLAG not in a else 1)"
  test "$(grep -c 'VOID (2026-08-09)' Trading-Bot-Rulesets.md)" -ge 2
  python -c "import re,sys; sys.exit(0 if re.search(r'armed_84_entries:\s*\d+\s*->\s*\d+', open('research/t6_rule84_arming.md').read()) else 1)"
  python research/regression_gate.py
  ```


### T7 -- two pools, two scoreboards
- model: deepseek
- depends-on: (none)

Austin trades two distinct universes and wants them scored apart: the **equity pool** (the 14
highest-options-volume US names; META is #14 at ~498k) and the **index pool** (QQQ, SPY, IWM plus
index futures), which is the prop-firm / high-leverage side. Same detection rules, separate
numbers — because 49% of all S marks are QQQ/SPY/IWM while `config.yaml`'s current watchlist
carries AAPL, AMD, META, AMZN and INTC, which have close to zero S marks between them.

Add to `config.yaml`, alongside the existing `watchlist` (leave it in place; nothing may change
which symbols are scanned in this version):

```yaml
pools:
  index: [QQQ, SPY, IWM]
  equity: []   # populated from research/priority_pool.json
```

`research/priority_pool.json` **is on main** (commit `48d3237`) and carries Austin's answer:
`equity_pool_14` = NVDA, TSLA, SPCX, PLTR, AAPL, MU, MSTR, AMZN, HTZ, MSFT, INTC, AMD, GOOGL,
META; `index_pool` = QQQ, SPY, IWM; `index_futures` = /ES, /NQ. Read it and write
`equity_pool_14` into `pools.equity` and `index_pool` into `pools.index`. Note in the report that
**SPCX, HTZ and MSTR have no `data_archive/` coverage**, so no historical recall can be computed
for them — say which of the 14 are and are not measurable rather than silently dropping them.

Then extend `research/t4_engine_recall.py` so its report breaks recall and precision out by pool
(`index`, `equity`, `other`) in addition to the existing overall numbers — additive only, do not
change the overall figures or the file's existing output format, since `regression_gate.py` parses
it. Write `research/t7_pools.md` with the per-pool table and, on its own line:

    pools_configured: index=<n> equity=<n>
    equity_pool_measurable: <n>/14

- **done-when:** `config.yaml` has a `pools:` block with an `index` list of 3; `research/t7_pools.md`
  carries the grep line and a per-pool recall table; `research/regression_gate.py` exits 0.
- **verify:**
  ```bash
  python -c "import yaml,sys; c=yaml.safe_load(open('config.yaml')); p=c.get('pools') or {}; sys.exit(0 if len(p.get('index') or [])==3 and 'equity' in p else 1)"
  python -c "import re,sys; t=open('research/t7_pools.md').read(); sys.exit(0 if re.search(r'pools_configured:\s*index=\d+\s+equity=\d+',t) and re.search(r'equity_pool_measurable:\s*\d+/14',t) else 1)"
  python -c "import yaml,sys; c=yaml.safe_load(open('config.yaml')); sys.exit(0 if len(c['pools']['equity'])==14 else 1)"
  python research/regression_gate.py
  ```


### T8 -- verdict: S-only vs today's trading set, side by side
- model: glm
- depends-on: everything

Read-only synthesis plus one measurement. Style: `research/v38_verdict.md` — cite files, do not
invent numbers.

The measurement: run the existing backtester twice over the same window — once as today
(`_SKIP_GRADES = ("X","D")`, i.e. A+/A/B/C all trade) and once with the trading set restricted to
`austin_tier == "S"` (force `TRADE_S_ONLY` True in-process only; **do not commit it True**).
Report win rate, expectancy in R, trade count and total P&L for both arms. Context Austin has
already ruled on and which this row must quote rather than argue with: `research/detect_wide.md:161`
says engine-grade **B is the only profitable tier (+$62,451 at 36.6% over 693 trades)** while A+
and A lose — and Austin's ruling is *"the only reason B makes money is because of the massive
amounts of trades; it doesn't prove edge, because none of it is accurate to a system."* Report
both arms honestly and recommend; **arm nothing.**

Write `research/v39_verdict.md` covering: (1) the new taxonomy from T1/T2 — how many S misses are
actually One Candle Rule candidates and how many are `timing_miss`; (2) the v3 corpus size from
T3 and S-grade fired recall measured on it vs the 10/77 = 13.0% v2 baseline; (3) the S-only vs
all-grades backtest table; (4) per-pool recall from T7; (5) what the 95% target needs next, in one
paragraph, naming the single biggest remaining lever.

Three grep-able lines, in this exact form:

    s_fired_recall_v3: <n>/<total>
    s_only_trades: <n>
    htf_hard_S: <n>
    htf_fill_override_S: <n>
    gate exit code: 0

Last line of the file, for the notification and for [[omen-3.9-homework]]: a section
`## FOR AUSTIN` of at most six numbered one-line findings.

- **done-when:** `research/v39_verdict.md` exists, carries all three grep lines and a
  `## FOR AUSTIN` section, and `research/regression_gate.py` exits 0.
- **verify:**
  ```bash
  python research/regression_gate.py
  python -c "import re,sys; t=open('research/v39_verdict.md').read(); sys.exit(0 if re.search(r's_fired_recall_v3:\s*\d+/\d+',t) and re.search(r's_only_trades:\s*\d+',t) and re.search(r'htf_hard_S:\s*\d+',t) and re.search(r'htf_fill_override_S:\s*\d+',t) and re.search(r'gate exit code:\s*0',t,re.I) and '## FOR AUSTIN' in t else 1)"
  python -c "import signal_runner as s,sys; sys.exit(0 if s.TRADE_S_ONLY is False else 1)"
  ```

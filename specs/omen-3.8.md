# OMEN 3.8 - close the label-routing bug, stop-bailing consolidation gate, and no_break_retest recall ceiling, with a hard regression gate

status: ready
version: omen-3.8
repo: aharger3/tradingbot
doc: Projects/OMEN-CONSOLIDATED.md

target: land three real production-code fixes (label routing, consolidation bail, break-retest
geometry) plus a Rule 7/10 rewrite, each measured against a locked baseline so no fix that chases
recall is allowed to drop a mark the engine already fires correctly today.

**Read this framing once; no row re-derives it.**

Baseline going in (`research/v37_verdict.md`, `research/engine_recall.md`): engine fires an
S-graded signal on 10/77 S bars (13% recall), any-signal S recall ceiling 27/77 (35%), below the
40% gate. `research/miss_autopsy.md`'s miss-reason table: `no_break_retest` = 27/77 S misses
(35% of all S bars, 40.3% of genuine misses) — the single largest lever. `vetoed_htf` and
`fired_wrong_bar` are next at 10 each (13%).

**T1's target is corrected from the doc's prior framing — verify before you code.** The doc
(`OMEN-CONSOLIDATED.md`, settled input #1, dated 2026-08-07) says three setups share
`SignalType.ONE_CANDLE_RULE`. That was already fixed by omen-3.7 T5 (PR #11, commit ac2f32c6):
`signal_runner.py` now routes FVG to `SignalType.FAIR_VALUE_GAP` and flag breakouts to
`SignalType.FLAG` — only the two order-block sides (long/short, legitimately one setup) still
share `ONE_CANDLE_RULE`. **But that fix is incomplete and currently broken on `origin/main`:**
`omen_bot.py`'s `SignalType` enum (line 8-12) only defines `BREAK_AND_RETEST`, `ONE_CANDLE_RULE`,
`REENTRY_84_RULE`, `NONE` — it never got `FAIR_VALUE_GAP` or `FLAG` added. `signal_runner.py`
references `SignalType.FAIR_VALUE_GAP` (line 700, 893) and `SignalType.FLAG` (line 752, 939),
which raises `AttributeError` at runtime the moment an FVG or flag setup fires. Verified live:
`python -c "import omen_bot; print([m.name for m in omen_bot.SignalType])"` on `origin/main`
prints only 4 members, missing both. This is the actual production bug T1 fixes — not a routing
split, an enum omission that crashes the scanner mid-session.

### T0 -- lock the baseline and build the regression gate
- model: opus
- depends-on: (none)

Run `research/t4_engine_recall.py` against `research/austin_marks_v2.jsonl` (159 marks) exactly
as-is, unmodified — this is the existing recall harness, reuse it, do not rewrite it. Capture its
`research/engine_entries.jsonl` output and derive the exact set of mark keys (`symbol|day|entry_i`
from `austin_marks_v2.jsonl`, joined to engine entries within the harness's existing +/-2 bar
tolerance) that currently fire, split by tier (S/A/X) and by signal grade (any-signal vs S-grade).
Write this locked set to `research/baseline_3.8.json`: `{"any_signal_fired": [...mark keys...],
"s_grade_fired": [...mark keys...], "precision": <float from engine_recall.md>}`.

Then write `research/regression_gate.py`: a script that re-runs `t4_engine_recall.py`'s detection
over the same 159 marks, computes the current fired-mark-key set the same way, diffs it against
`research/baseline_3.8.json`, and exits non-zero (printing the exact dropped mark keys) if any
baseline-fired key — any_signal or S-grade — is no longer fired. It must NOT fail on new fires
(recall going up is fine); it only fails on regressions (a previously-fired mark going silent).
T1/T2/T3 each run this gate after their change and report its exit code.

- **done-when:** `research/baseline_3.8.json` exists with non-empty `any_signal_fired` and
  `s_grade_fired` lists; `python research/regression_gate.py` run immediately after T0 (no code
  changed yet) exits 0.

### T2 -- add missing SignalType enum members and stop the FVG/flag crash
- model: glm
- depends-on: T0

`omen_bot.py` line 8-12: add `FAIR_VALUE_GAP = "fair_value_gap"` and `FLAG = "flag"` to the
`SignalType` enum, matching the pattern of the existing members. This is the actual bug — see the
framing above. Do not touch `signal_runner.py`'s routing, which is already correct; only the enum
is missing members. After the change, run `python -c "import omen_bot; import signal_runner"` to
confirm no import-time error, then run `research/regression_gate.py`
(`python research/regression_gate.py`) and confirm exit 0 — this change only adds enum values, it
cannot change engine detection, so any regression here means something else broke.

- **done-when:** `python -c "import omen_bot; print(sorted(m.name for m in
  omen_bot.SignalType))"` includes `FAIR_VALUE_GAP` and `FLAG`, AND
  `python research/regression_gate.py` exits 0.

### T3 -- stop `_is_consolidation` from abandoning the bar on clustered levels
- model: glm
- depends-on: T0

`signal_runner.py`'s `_is_consolidation` (currently ~line 495 on `origin/main`, confirm with
`grep -n "_is_consolidation" signal_runner.py` since line numbers drift): returns `True` (skip
all signals for the bar) whenever PDH/PDL/OR-high/OR-low are all within 0.5% of their average.
Austin's ruling (`OMEN-CONSOLIDATED.md`, settled input #2, 2026-08-07): clustered levels are NOT
a no-trade gate — one level broken and retested cleanly is enough to trade. Change
`_is_consolidation` so a clustered-levels bar no longer hard-skips; instead let the normal
break-and-retest / order-block / FVG detection run against whichever single level the bar
actually breaks and retests, and only fall through to "no signal" if none of them fire (the
existing per-setup logic already handles that case — do not add a new bypass path, just stop the
early `return []`/`return True` short-circuit). Keep the function's docstring accurate to its new
behavior. Run `research/regression_gate.py` after.

- **done-when:** `research/regression_gate.py` exits 0, AND a fresh
  `python research/t4_engine_recall.py` run shows `consolidation_early_return` miss count (from
  `research/miss_autopsy.py`'s reclassification, or a manual count of bars where
  `_is_consolidation` used to return `True`) is lower than the T0 baseline's count for that
  reason — write the before/after counts to `research/t3_consolidation_effect.md`.

### T4 -- fix the no_break_retest geometry, the single biggest recall lever
- model: glm
- depends-on: T3

`no_break_retest` is 27/77 S misses (35%) per `research/miss_autopsy.md` — `detect_break_retest`
(in `omen_bot.py`) returns falsy for every reference level on these bars. `research/t5_wide_probe.py`
already showed widening the retest-proximity tolerance alone (`DETECT_WIDE`) does NOT fix this —
it roughly doubles fired-S (10->14/77) but halves precision (38.5%->19.4%) and finds zero new
distinct S marks after dedup; do not re-arm `DETECT_WIDE` or re-run that experiment. Instead:
read `research/t5_wide_probe.py`'s per-mark output for the 27 S x `no_break_retest` marks (it
already lists them) and `detect_break_retest`'s actual break/retest test — diagnose why the
retest never registers on these specific marks (wrong reference level chosen, retest window too
narrow in a way tolerance-widening doesn't fix, wrong candle field checked, etc.) and correct the
geometry test itself, not its tolerance. Write findings and the exact fix to
`research/t4_geometry_fix.md` before editing code — name which of the 27 marks it recovers and
why, so T5 can cite it. Run `research/regression_gate.py` after the code change.

- **done-when:** `research/regression_gate.py` exits 0, AND a fresh `python research/t4_engine_recall.py`
  run shows S any-signal recall (currently 27/77) has increased with zero regressions — write the
  new recall number to `research/t4_geometry_fix.md`.

### T5 -- rewrite Rule 7 and Rule 10 as detection conditions, not thin bullets
- model: opus
- depends-on: T0

`Trading-Bot-Rulesets.md` currently states Rules 7 and 10 as one-line bullets with no detection
logic behind them — `research/rule7_rule10.md` found Rule 7 (retest speed) null for 76/159 marks
(47.8%, mostly "no break candle identifiable") and Rule 10 null for 56/159 (35.2%). Read
`research/rule7_rule10.md` in full for the exact feature definitions already built
(`bars_break_to_retest` for Rule 7; check the file's Rule 10 section for its feature). Rewrite
both rules in `Trading-Bot-Rulesets.md` as paragraph specs in the style of the existing rules
(e.g. Rule 6's "position management with breakeven scaling" entry — prose, not a bullet), each
naming a concrete, always-defined detection condition (no `null` outcome) that the engine can
evaluate on every bar, replacing the current break-candle-dependent null case. Wire the corrected
condition into `signal_runner.py`/`omen_bot.py` as real detection code (not doc-only), gated
behind a new default-OFF flag (matching the `S_GATE`/`DETECT_WIDE` pattern already in the file)
so this lands byte-identical to today until Austin arms it. Run `research/regression_gate.py`
after — the flag defaults OFF, so it must be a no-op on the gate.

- **done-when:** `Trading-Bot-Rulesets.md`'s Rule 7 and Rule 10 sections are paragraph specs with
  a named detection condition each, AND the new flag exists in code defaulting OFF, AND
  `research/regression_gate.py` exits 0.

### T6 -- final verdict: recall/precision vs T0 baseline, confirm zero regressions
- model: opus
- depends-on: everything

Run `research/t4_engine_recall.py` fresh (all T2-T5 changes landed, new Rule 7/10 flag still OFF
per T5). Run `research/regression_gate.py` one final time against `research/baseline_3.8.json`
and confirm exit 0. Write `research/v38_verdict.md` (style: `research/v37_verdict.md` — read-only
synthesis, cite `research/t3_consolidation_effect.md`, `research/t4_geometry_fix.md`, and the
gate's final exit code, no new numbers computed here) covering: final any-signal and S-grade
recall vs the T0 baseline (10/77 S, 27/77 any-signal), final precision vs baseline, explicit
confirmation zero baseline-fired marks regressed (quote the gate's output), and whether the 27/77
-> 40%-gate distance closed enough to revisit `DETECT_WIDE` or any new filter (do not arm
anything — recommend only).

- **done-when:** `research/v38_verdict.md` exists and states a final S-recall number, a final
  any-signal recall number, and the regression gate's final exit code (must be 0).

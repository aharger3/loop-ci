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

**T2 IS ALREADY DONE — corrected 2026-08-09, do not re-derive this.** The framing above it
claimed `omen_bot.py`'s `SignalType` enum was missing `FAIR_VALUE_GAP` and `FLAG` on
`origin/main` and that the scanner would `AttributeError` the moment an FVG or flag setup
fired. That was **false when the spec was written.** Commit `ac2f32c` (omen-3.7, PR #11,
merged 2026-08-08 04:54) added both members, and `signal_runner.py`'s routing to them was
correct already. Checked on `origin/main` 2026-08-09:
`git log -S'FAIR_VALUE_GAP = "fair_value_gap"' -- omen_bot.py` → `ac2f32c`.

T2 is marked `[x]` on that evidence — the artifact its check names exists on main, which is
the only ground on which a row may be checked off by hand. Its `verify:` is kept so a future
re-parse still proves it.

The general lesson, since this spec cost two runs to it: a claim of the form "verified live on
origin/main" in a spec written by a session that could not run code is **an assertion, not a
verification.** That is what `verify:` is for.

### [x] T0 -- lock the baseline and build the regression gate
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
- **verify:**
  ```bash
  python -c "import json,sys; d=json.load(open('research/baseline_3.8.json')); sys.exit(0 if d.get('any_signal_fired') and d.get('s_grade_fired') else 1)"
  python research/regression_gate.py
  ```

### [x] T2 -- add missing SignalType enum members and stop the FVG/flag crash
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
- **verify:**
  ```bash
  python -c "import omen_bot,signal_runner,sys; n={m.name for m in omen_bot.SignalType}; sys.exit(0 if {'FAIR_VALUE_GAP','FLAG'} <= n else 1)"
  python research/regression_gate.py
  ```

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

`research/t3_consolidation_effect.md` MUST contain, on its own line and in exactly this form,
the before/after miss counts — the runner greps for it and the row fails without it:

    consolidation_early_return: <before> -> <after>

- **done-when:** `research/regression_gate.py` exits 0, AND a fresh
  `python research/t4_engine_recall.py` run shows `consolidation_early_return` miss count (from
  `research/miss_autopsy.py`'s reclassification, or a manual count of bars where
  `_is_consolidation` used to return `True`) is lower than the T0 baseline's count for that
  reason — write the before/after counts to `research/t3_consolidation_effect.md`.
- **verify:**
  ```bash
  python research/regression_gate.py
  python -c "import re,sys; m=re.search(r'consolidation_early_return:\s*(\d+)\s*->\s*(\d+)', open('research/t3_consolidation_effect.md').read()); sys.exit(0 if m and int(m.group(2)) < int(m.group(1)) else 1)"
  ```

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

`research/t4_geometry_fix.md` MUST contain, on its own line and in exactly this form, the
before/after S any-signal recall counts out of 77 — the runner greps for it:

    s_any_signal_recall: 27 -> <after>

- **done-when:** `research/regression_gate.py` exits 0, AND a fresh `python research/t4_engine_recall.py`
  run shows S any-signal recall (currently 27/77) has increased with zero regressions — write the
  new recall number to `research/t4_geometry_fix.md`.
- **verify:**
  ```bash
  python research/regression_gate.py
  python -c "import re,sys; m=re.search(r's_any_signal_recall:\s*(\d+)\s*->\s*(\d+)', open('research/t4_geometry_fix.md').read()); sys.exit(0 if m and int(m.group(2)) > int(m.group(1)) else 1)"
  ```

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

Two names are fixed because the runner checks them, not because they read nicely: the flag is
`RULE_710_ENABLED = False` at module level in `signal_runner.py`, and each rewritten rule
contains a line beginning `**Detection condition:**` naming the always-defined condition.

- **done-when:** `Trading-Bot-Rulesets.md`'s Rule 7 and Rule 10 sections are paragraph specs with
  a named detection condition each, AND the new flag exists in code defaulting OFF, AND
  `research/regression_gate.py` exits 0.
- **verify:**
  ```bash
  python research/regression_gate.py
  test "$(grep -ci 'Detection condition:' Trading-Bot-Rulesets.md)" -ge 2
  python -c "import signal_runner,sys; sys.exit(0 if getattr(signal_runner, 'RULE_710_ENABLED', None) is False else 1)"
  ```

### T6 -- final verdict: recall/precision vs T0 baseline, confirm zero regressions
- model: glm
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

The verdict must carry three grep-able lines, in this exact form:

    s_grade_recall: <n>/77
    any_signal_recall: <n>/77
    gate exit code: 0

- **done-when:** `research/v38_verdict.md` exists and states a final S-recall number, a final
  any-signal recall number, and the regression gate's final exit code (must be 0).
- **verify:**
  ```bash
  python research/regression_gate.py
  python -c "import re,sys; t=open('research/v38_verdict.md').read(); sys.exit(0 if re.search(r's_grade_recall:\s*\d+/77',t) and re.search(r'any_signal_recall:\s*\d+/77',t) and re.search(r'gate exit code:\s*0',t,re.I) else 1)"
  ```


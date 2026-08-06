# OMEN 3.5 - re-grade the marks, fix the veto, re-run

status: void
version: omen-3.5

VOID 2026-08-06. T1's whole premise was wrong: the 162 verdicts share ZERO (symbol, day) pairs
with `research/blind_marks_all.jsonl`, so there was nothing to re-grade - they are a separate
marking session. T3's HOD/LOD fix is done and merged to tradingbot main (PR #7). T2, T4 and T5
are carried forward as omen-3.6's T3, T6 and T8. Do not re-run this spec.
repo: aharger3/tradingbot
doc: Projects/omen-trading.md

target: apply Austin's fresh tier re-grade to the marks corpus, fix the one-line HOD/LOD bug
3.4 identified, and re-run H3 (veto) and H9 (confluence) against corrected inputs to see whether
either clears the effect floor once the definitions are honest.

Framing, so no row re-derives it: `research/v34_verdict.md` on this repo's main is the prior
version's closed verdict - read it, do not recompute anything it already reports. Two findings
from it govern this version:

1. **The veto (H3) was measuring "did this trade make a new high," not "is there a wall ahead."**
   `research/levels.py`'s `hod_lod_nodes()` computes the session high/low through and including
   the entry bar, so for a breakout entry the nearest wall is almost always the bar's own extreme
   (96.9% of trades). One-line fix, not yet applied: `research/levels.py` line 137,
   `seg = bars[: entry_i + 1]` -> `seg = bars[: entry_i]`. H3 and H9 must be re-run after it -
   H9's weight-3.0 bucket composition changes too.
2. **T3 (mark-defect audit) was checked done on both prior runs and never produced its file.**
   `research/marks_clean.jsonl` exists but carries none of the three required booleans
   (`smeared`, `incoherent`, `sub_1r`). This version's T2 is that row, done for real this time.

Same statistical floor as 3.4, not to be renegotiated inside a row: **4 percentage points of win
rate, or Cohen's d = 0.15**. Block-bootstrap over whole trading days (10,000 resamples) for every
CI. Correct multiple hypotheses with **BH-FDR at q = 0.10**.

## Tasks

### T1 -- Apply Austin's tier re-grade to the marks corpus

- model: deepseek

Austin hand-reviewed 162 previously-marked entries and reassigned their tier. This is a
**re-grade of existing marks**, not new marks - match by the identity triple
`symbol|day|entry_i` against `research/blind_marks_all.jsonl`, do not create new records.

```json
[{"symbol":"HOOD","day":"2025-08-04","entry_i":40,"verdict":"a"},{"symbol":"SOFI","day":"2026-03-11","entry_i":63,"verdict":"a"},{"symbol":"QQQ","day":"2025-06-25","entry_i":48,"verdict":"a"},{"symbol":"SPY","day":"2026-01-08","entry_i":42,"verdict":"x"},{"symbol":"MSFT","day":"2026-02-11","entry_i":20,"verdict":"a"},{"symbol":"QQQ","day":"2025-02-26","entry_i":28,"verdict":"s"},{"symbol":"SPY","day":"2026-02-09","entry_i":24,"verdict":"a"},{"symbol":"HOOD","day":"2026-05-19","entry_i":19,"verdict":"a"},{"symbol":"META","day":"2025-09-23","entry_i":9,"verdict":"a"},{"symbol":"NVDA","day":"2024-11-19","entry_i":18,"verdict":"a"},{"symbol":"COIN","day":"2025-10-21","entry_i":8,"verdict":"s"},{"symbol":"IWM","day":"2026-07-24","entry_i":29,"verdict":"s"},{"symbol":"QQQ","day":"2025-06-24","entry_i":15,"verdict":"s"},{"symbol":"META","day":"2026-06-10","entry_i":18,"verdict":"x"},{"symbol":"SPY","day":"2024-10-22","entry_i":41,"verdict":"a"},{"symbol":"MARA","day":"2025-08-18","entry_i":23,"verdict":"x"},{"symbol":"IWM","day":"2024-04-03","entry_i":13,"verdict":"s"},{"symbol":"IWM","day":"2024-04-03","entry_i":73,"verdict":"s"},{"symbol":"IWM","day":"2024-04-03","entry_i":73,"verdict":"s"},{"symbol":"AMZN","day":"2025-08-14","entry_i":18,"verdict":"x"},{"symbol":"CRM","day":"2025-07-02","entry_i":17,"verdict":"a"},{"symbol":"MARA","day":"2025-04-02","entry_i":14,"verdict":"a"},{"symbol":"BABA","day":"2025-07-22","entry_i":20,"verdict":"s"},{"symbol":"TSM","day":"2025-10-07","entry_i":74,"verdict":"a"},{"symbol":"QQQ","day":"2024-12-23","entry_i":47,"verdict":"a"},{"symbol":"CRM","day":"2026-05-07","entry_i":18,"verdict":"x"},{"symbol":"IWM","day":"2025-12-01","entry_i":11,"verdict":"s"},{"symbol":"SPY","day":"2026-03-25","entry_i":10,"verdict":"x"},{"symbol":"AMD","day":"2026-04-21","entry_i":35,"verdict":"a"},{"symbol":"GOOGL","day":"2025-08-07","entry_i":18,"verdict":"s"},{"symbol":"QQQ","day":"2024-05-08","entry_i":8,"verdict":"s"},{"symbol":"HOOD","day":"2025-03-04","entry_i":44,"verdict":"s"},{"symbol":"INTC","day":"2025-06-05","entry_i":10,"verdict":"x"},{"symbol":"QQQ","day":"2024-03-05","entry_i":11,"verdict":"a"},{"symbol":"QQQ","day":"2024-03-05","entry_i":21,"verdict":"s"},{"symbol":"QQQ","day":"2025-03-17","entry_i":16,"verdict":"s"},{"symbol":"SPY","day":"2024-04-03","entry_i":9,"verdict":"s"},{"symbol":"GOOG","day":"2025-06-10","entry_i":21,"verdict":"a"},{"symbol":"QQQ","day":"2026-02-11","entry_i":32,"verdict":"s"},{"symbol":"QQQ","day":"2026-02-11","entry_i":45,"verdict":"s"},{"symbol":"SPY","day":"2025-02-21","entry_i":18,"verdict":"x"},{"symbol":"IWM","day":"2025-09-05","entry_i":12,"verdict":"s"},{"symbol":"IWM","day":"2025-09-05","entry_i":51,"verdict":"a"},{"symbol":"QQQ","day":"2025-12-05","entry_i":27,"verdict":"s"},{"symbol":"QQQ","day":"2025-12-05","entry_i":35,"verdict":"s"},{"symbol":"CRM","day":"2025-06-02","entry_i":27,"verdict":"s"},{"symbol":"QQQ","day":"2025-03-18","entry_i":13,"verdict":"s"},{"symbol":"SPY","day":"2025-06-02","entry_i":40,"verdict":"a"},{"symbol":"QQQ","day":"2024-01-04","entry_i":41,"verdict":"s"},{"symbol":"MSFT","day":"2026-01-20","entry_i":12,"verdict":"s"},{"symbol":"IWM","day":"2024-02-28","entry_i":9,"verdict":"s"},{"symbol":"IWM","day":"2024-02-28","entry_i":18,"verdict":"a"},{"symbol":"AMZN","day":"2026-07-17","entry_i":7,"verdict":"a"},{"symbol":"COIN","day":"2026-03-04","entry_i":43,"verdict":"a"},{"symbol":"MU","day":"2025-11-07","entry_i":22,"verdict":"s"},{"symbol":"QQQ","day":"2025-01-16","entry_i":23,"verdict":"s"},{"symbol":"QQQ","day":"2025-12-30","entry_i":24,"verdict":"s"},{"symbol":"GOOG","day":"2025-12-08","entry_i":58,"verdict":"x"},{"symbol":"TSLA","day":"2026-02-18","entry_i":42,"verdict":"s"},{"symbol":"QQQ","day":"2024-10-03","entry_i":18,"verdict":"s"},{"symbol":"UBER","day":"2026-06-09","entry_i":11,"verdict":"a"},{"symbol":"NVDA","day":"2024-11-18","entry_i":10,"verdict":"s"},{"symbol":"QQQ","day":"2025-05-16","entry_i":63,"verdict":"a"},{"symbol":"IWM","day":"2025-04-10","entry_i":16,"verdict":"s"},{"symbol":"MARA","day":"2025-05-14","entry_i":23,"verdict":"x"},{"symbol":"GOOGL","day":"2024-09-03","entry_i":10,"verdict":"a"},{"symbol":"ORCL","day":"2025-11-03","entry_i":17,"verdict":"s"},{"symbol":"ORCL","day":"2025-03-28","entry_i":12,"verdict":"s"},{"symbol":"IWM","day":"2025-10-21","entry_i":9,"verdict":"s"},{"symbol":"HOOD","day":"2025-02-24","entry_i":16,"verdict":"a"},{"symbol":"QQQ","day":"2024-08-23","entry_i":36,"verdict":"s"},{"symbol":"UBER","day":"2025-09-11","entry_i":15,"verdict":"s"},{"symbol":"GOOGL","day":"2024-10-15","entry_i":32,"verdict":"s"},{"symbol":"NVDA","day":"2024-12-16","entry_i":12,"verdict":"a"},{"symbol":"MSFT","day":"2025-03-04","entry_i":13,"verdict":"s"},{"symbol":"QQQ","day":"2025-01-10","entry_i":13,"verdict":"s"},{"symbol":"TSLA","day":"2024-03-27","entry_i":13,"verdict":"s"},{"symbol":"QQQ","day":"2026-03-04","entry_i":42,"verdict":"s"},{"symbol":"MARA","day":"2026-07-09","entry_i":19,"verdict":"s"},{"symbol":"CRM","day":"2025-11-18","entry_i":16,"verdict":"a"},{"symbol":"NVDA","day":"2024-12-30","entry_i":34,"verdict":"a"},{"symbol":"MU","day":"2026-01-28","entry_i":13,"verdict":"s"},{"symbol":"SPY","day":"2025-09-25","entry_i":45,"verdict":"a"},{"symbol":"HOOD","day":"2026-04-13","entry_i":16,"verdict":"s"},{"symbol":"SPY","day":"2025-02-20","entry_i":35,"verdict":"a"},{"symbol":"TSM","day":"2026-05-29","entry_i":23,"verdict":"s"},{"symbol":"GOOG","day":"2026-02-23","entry_i":19,"verdict":"x"},{"symbol":"MARA","day":"2026-07-17","entry_i":13,"verdict":"a"},{"symbol":"SPY","day":"2024-02-22","entry_i":25,"verdict":"a"},{"symbol":"UBER","day":"2026-01-06","entry_i":22,"verdict":"a"},{"symbol":"SPY","day":"2025-11-05","entry_i":52,"verdict":"a"},{"symbol":"QQQ","day":"2024-02-01","entry_i":44,"verdict":"x"},{"symbol":"SPY","day":"2026-03-03","entry_i":17,"verdict":"s"},{"symbol":"IWM","day":"2024-03-22","entry_i":24,"verdict":"s"},{"symbol":"SPY","day":"2025-03-18","entry_i":13,"verdict":"s"},{"symbol":"PLTR","day":"2024-10-23","entry_i":21,"verdict":"s"},{"symbol":"QQQ","day":"2026-07-09","entry_i":11,"verdict":"s"},{"symbol":"ORCL","day":"2026-06-09","entry_i":8,"verdict":"a"},{"symbol":"SPY","day":"2026-05-05","entry_i":10,"verdict":"a"},{"symbol":"AMD","day":"2026-05-14","entry_i":25,"verdict":"a"},{"symbol":"HOOD","day":"2026-02-05","entry_i":40,"verdict":"s"},{"symbol":"TSLA","day":"2024-12-03","entry_i":8,"verdict":"a"},{"symbol":"IWM","day":"2024-08-22","entry_i":27,"verdict":"s"},{"symbol":"COIN","day":"2025-12-01","entry_i":11,"verdict":"a"},{"symbol":"QQQ","day":"2024-01-30","entry_i":35,"verdict":"x"},{"symbol":"ORCL","day":"2025-07-08","entry_i":7,"verdict":"s"},{"symbol":"TSLA","day":"2024-06-24","entry_i":9,"verdict":"s"},{"symbol":"UBER","day":"2026-07-06","entry_i":12,"verdict":"s"},{"symbol":"QQQ","day":"2026-03-06","entry_i":47,"verdict":"x"},{"symbol":"MARA","day":"2025-07-30","entry_i":30,"verdict":"a"},{"symbol":"MARA","day":"2024-09-09","entry_i":38,"verdict":"x"},{"symbol":"IWM","day":"2026-06-24","entry_i":28,"verdict":"a"},{"symbol":"MARA","day":"2024-10-18","entry_i":11,"verdict":"s"},{"symbol":"HOOD","day":"2026-07-07","entry_i":37,"verdict":"a"},{"symbol":"TSLA","day":"2024-02-05","entry_i":16,"verdict":"a"},{"symbol":"MU","day":"2025-12-08","entry_i":12,"verdict":"x"},{"symbol":"UBER","day":"2025-07-31","entry_i":48,"verdict":"a"},{"symbol":"PLTR","day":"2026-03-31","entry_i":23,"verdict":"s"},{"symbol":"IWM","day":"2026-05-28","entry_i":46,"verdict":"s"},{"symbol":"MARA","day":"2024-12-17","entry_i":49,"verdict":"s"},{"symbol":"SPY","day":"2025-12-02","entry_i":14,"verdict":"x"},{"symbol":"AMD","day":"2025-06-05","entry_i":6,"verdict":"s"},{"symbol":"IWM","day":"2024-08-01","entry_i":44,"verdict":"a"},{"symbol":"QQQ","day":"2024-03-15","entry_i":11,"verdict":"s"},{"symbol":"MSFT","day":"2026-06-10","entry_i":17,"verdict":"a"},{"symbol":"UBER","day":"2025-02-07","entry_i":22,"verdict":"s"},{"symbol":"CRM","day":"2025-09-26","entry_i":12,"verdict":"a"},{"symbol":"PLTR","day":"2025-09-18","entry_i":14,"verdict":"s"},{"symbol":"SOFI","day":"2024-10-30","entry_i":16,"verdict":"s"},{"symbol":"QQQ","day":"2025-01-28","entry_i":40,"verdict":"a"},{"symbol":"QQQ","day":"2024-12-16","entry_i":28,"verdict":"s"},{"symbol":"MARA","day":"2026-07-20","entry_i":11,"verdict":"a"},{"symbol":"SOFI","day":"2026-05-20","entry_i":55,"verdict":"a"},{"symbol":"NVDA","day":"2025-03-25","entry_i":25,"verdict":"a"},{"symbol":"COIN","day":"2025-06-26","entry_i":18,"verdict":"s"},{"symbol":"TSLA","day":"2024-01-12","entry_i":18,"verdict":"x"},{"symbol":"QQQ","day":"2025-05-07","entry_i":31,"verdict":"a"},{"symbol":"HOOD","day":"2025-12-29","entry_i":12,"verdict":"x"},{"symbol":"ORCL","day":"2025-09-17","entry_i":11,"verdict":"a"},{"symbol":"AMD","day":"2026-03-04","entry_i":9,"verdict":"a"},{"symbol":"AMZN","day":"2026-04-10","entry_i":74,"verdict":"a"},{"symbol":"UBER","day":"2025-08-13","entry_i":25,"verdict":"s"},{"symbol":"IWM","day":"2025-12-04","entry_i":56,"verdict":"s"},{"symbol":"IWM","day":"2024-09-24","entry_i":35,"verdict":"x"},{"symbol":"IWM","day":"2024-09-24","entry_i":53,"verdict":"x"},{"symbol":"HOOD","day":"2026-07-10","entry_i":23,"verdict":"s"},{"symbol":"SPY","day":"2025-07-01","entry_i":41,"verdict":"a"},{"symbol":"GOOG","day":"2025-04-04","entry_i":26,"verdict":"a"},{"symbol":"SPY","day":"2024-06-11","entry_i":23,"verdict":"s"},{"symbol":"SPY","day":"2026-03-02","entry_i":24,"verdict":"s"},{"symbol":"COIN","day":"2026-04-09","entry_i":30,"verdict":"s"},{"symbol":"SPY","day":"2026-03-05","entry_i":56,"verdict":"s"},{"symbol":"NVDA","day":"2026-05-21","entry_i":10,"verdict":"a"},{"symbol":"MSFT","day":"2025-03-20","entry_i":28,"verdict":"s"},{"symbol":"BABA","day":"2025-12-26","entry_i":36,"verdict":"a"},{"symbol":"QQQ","day":"2025-07-01","entry_i":72,"verdict":"x"},{"symbol":"QQQ","day":"2025-07-01","entry_i":72,"verdict":"x"},{"symbol":"QQQ","day":"2025-07-01","entry_i":72,"verdict":"x"},{"symbol":"SPY","day":"2025-11-19","entry_i":9,"verdict":"s"},{"symbol":"SPY","day":"2024-09-19","entry_i":19,"verdict":"s"},{"symbol":"QQQ","day":"2025-02-25","entry_i":16,"verdict":"s"},{"symbol":"QQQ","day":"2025-02-25","entry_i":53,"verdict":"a"}]
```

Verdict codes: `s`/`a`/`x` map to tiers S/A/X (drop the old B tier per the S/A/C/X ladder in
`Projects/omen-corpus-plan.md` - if a matched record currently carries `tier: "B"` or `"C"`,
overwrite it too). Duplicate `(symbol, day, entry_i)` triples in the input (a few exist) mean
"marked twice" - keep the later occurrence in file order, do not error.

Write `research/regrade_audit.md`: total input rows, matched count, unmatched count (list every
unmatched triple explicitly - the marking tool's timestamp/index may not line up with the
corpus's, and an unmatched triple is a data problem worth seeing, not a silent skip), and a
before/after tier distribution table. Write the updated corpus back to
`research/blind_marks_all.jsonl` in place (same schema, only `tier` changed on matched rows).

- **done-when:** `research/regrade_audit.md` exists and states matched/unmatched counts that sum to 162, and `research/blind_marks_all.jsonl` has the same line count it had before this row ran.

### T2 -- The real T3: mark-defect audit (3.4's version never wrote its file)

- model: deepseek
- depends-on: T1

Same spec as 3.4's T3, actually executed this time. Read `research/blind_marks_all.jsonl`
(post-regrade). For every mark compute three booleans:

- `smeared`: shares a `symbol|day|marked_at` with at least one other mark (per-chart tier/tags
  were captured once per chart and copied onto every entry from that chart).
- `incoherent`: `side == "call"` and `target <= entry`, or `side == "put"` and `target >= entry`.
- `sub_1r`: `rr < 1.0`.

Write `research/marks_audit.md` (count of each defect, median rr) and overwrite
`research/marks_clean.jsonl` with every mark carrying all three booleans plus its (possibly
updated) tier from T1.

- **done-when:** `research/marks_audit.md` exists and states a count for each of the three defects, and every line in `research/marks_clean.jsonl` has `smeared`, `incoherent`, and `sub_1r` keys.

### T3 -- Fix the HOD/LOD off-by-one in levels.py

- model: glm

`research/levels.py`, `hod_lod_nodes()`, line 137: change `seg = bars[: entry_i + 1]` to
`seg = bars[: entry_i]`. The session high/low must be computed from bars *before* the entry bar,
not through it - per `research/v34_verdict.md` §2, computing it through the entry bar makes the
"nearest wall" almost always the entry bar's own extreme (96.9% of trades), which is why the veto
fired at 42-64% instead of a sane rate.

Update `research/test_levels.py`'s existing HOD/LOD case (or add one) to assert the session
extreme excludes the entry bar itself - construct a bar sequence where the entry bar is the new
high and assert `hod_lod_nodes()` returns the *prior* high, not the entry bar's.

- **done-when:** `python research/test_levels.py` exits 0, and `python research/levels.py --selftest` still prints a level set with every entry carrying `available_from`.

### T4 -- Re-run H3 (veto) and H9 (confluence) against corrected inputs

- model: deepseek
- depends-on: T2, T3

Re-run `research/h3_veto.py` and `research/h9_confluence.py` unchanged except for reading the
fixed `research/levels.py` and the re-graded `research/marks_clean.jsonl`. Same four-threshold
sweep for H3 (0.8R/1.0R/1.2R/1.5R), same weight-bucket table for H9. Overwrite
`research/h3_veto.md` and `research/h9_confluence.md` in place; keep the prior versions as
`research/h3_veto.PRE-FIX.md` and `research/h9_confluence.PRE-FIX.md` so the before/after is on
disk, not just in memory.

Report explicitly, at the top of each new file: the veto rate at each threshold (the validity
band is 5-40% - if it's still outside that band, the fix did not do what it was supposed to and
say so plainly) and how many of H9's weight-bucket assignments changed vs. the PRE-FIX version.

- **done-when:** `research/h3_veto.md` and `research/h9_confluence.md` both exist, each states the veto rate or bucket-change count in its first 10 lines, and both `.PRE-FIX.md` backups exist.

### T5 -- Verdict

- model: opus
- depends-on: everything

Read `research/regrade_audit.md`, `research/marks_audit.md`, `research/h3_veto.md`,
`research/h9_confluence.md`, and their `.PRE-FIX.md` counterparts. Do not recompute any number.

Apply the same floor as 3.4 (4 points WR or d=0.15) and BH-FDR at q=0.10. Answer:

1. **Is the veto rate now inside its own 5-40% validity band?** If not, the HOD/LOD fix wasn't
   sufficient and name the next suspect.
2. **Did fixing the definition change the H3/H9 verdict, or just the diagnostic numbers?** 3.4's
   headline was "0 of 8 hypotheses cleared BH-FDR" - state plainly whether that count changed.
3. **What is the one change to make next** - or state that nothing testable is left in this
   thread and the next lever is more marks, not more analysis.

Write `research/v35_verdict.md`, ending with a `FOR AUSTIN` section of ten lines or fewer.

- **done-when:** `research/v35_verdict.md` exists, answers all three numbered questions, and ends with a `FOR AUSTIN` section of ten lines or fewer.

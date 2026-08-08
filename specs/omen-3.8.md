# OMEN 3.8 - fix the recall harness's dedupe-before-join bug

status: ready
version: omen-3.8
repo: aharger3/tradingbot
doc: Projects/OMEN-CONSOLIDATED.md

target: fix the one measurement bug omen-3.7's verdict (`research/v37_verdict.md`) named as the
single prerequisite before any further OMEN work, then re-measure `DETECT_WIDE` OFF vs ON with
the corrected harness. This version changes no production code and arms no flag — it is a
measurement fix only.

**Read this framing once; no row re-derives it.**

3.7 merged 2026-08-08. Its verdict (`research/v37_verdict.md`, section 5) found a 19-mark
contradiction inside `research/recall_ab.md`: deduped any-signal S recall is flat at 27/77 across
both arms (the basis for "DETECT_WIDE finds zero new S detections"), while the raw no-dedupe
any-signal S recall rises 29/77 -> 46/77 in the same file. T5 (3.7) predicted DETECT_WIDE would
newly reach 9 S marks; T6 (3.7)'s deduped headline says 0. One of those is wrong, and the verdict
traced why: the dedupe is a **day-wide, mark-blind window**, applied before any mark is ever
consulted.

**The defect, precisely.** `research/t4_engine_recall.py`'s `run_day` (called by
`research/t6_recall_ab.py` for both arms) replays a whole trading day bar-by-bar and dedupes
signals into `all_sigs` / `entries` using a `(signal_type, direction, idea) -> last_seen_bar`
map with a `DEDUPE_BARS`-wide window (`seen_any` / `seen` at lines ~166-198): the **first**
occurrence of an idea within any `DEDUPE_BARS` window of a **prior** occurrence of the same idea
is kept, and every later repeat is silently dropped — regardless of where any mark's `entry_i`
falls. Only after this whole-day collapse does `main()` join the survivors against each mark
within `+/-TOL` (2) bars (`hit = any(abs(b - m["entry_i"]) <= TOL for b in ent_bars)`). A wider
retest tolerance (`DETECT_WIDE=True`) makes the engine re-fire the same idea on more candles; if
an earlier, mark-irrelevant occurrence of that idea already claimed the dedupe slot for the day,
the occurrence that actually lands next to the mark never survives to be joined — so the mark
reads as a miss even though the engine detected it right there. This is exactly what the raw
(no-dedupe) column shows moving (29->46) while the deduped column cannot (27->27): raw is not
window-collapsed at all, so it cannot hide a mark-adjacent hit behind an earlier unrelated one,
but it also is not a real per-mark measurement — it is a coarser upper bound that says nothing
about whether the *nearby* hit is the same repeated idea or two genuinely different setups.

**The fix.** Join before you dedupe, not after. For each mark, the detection question is "did
any raw captured signal (from `raw_sigs`, already computed and already returned by `run_day`,
completely unused for this purpose today) land within `+/-TOL` bars of this mark's `entry_i`" —
answer that directly per mark, per arm, per grade-bucket (fired-only and any-grade), with **no
day-wide window collapse involved at all**. Only *after* that per-mark join should repeat counting
be prevented, and only within the marks themselves: if two marks in `austin_marks_v2.jsonl` are
close enough that the same raw signal could satisfy both (should not happen at this project's mark
density, but assert it rather than assume it), count that signal once, not twice, and say in the
report whether it ever happened.

- Facts each row would otherwise have to rediscover: `research/t4_engine_recall.py`'s `run_day`
  already returns `(entries, all_sigs, raw_sigs)` — `raw_sigs` is the undeduped list, already
  computed, already threaded through `main()` for the existing raw-upper-bound column (lines
  ~261-262). Nothing needs to be recomputed from the engine; this is a re-aggregation of data
  already produced. `DEDUPE_BARS` and `TOL` (`= 2`) are both module constants already defined.
- `research/t6_recall_ab.py` is a thin wrapper that points `t4_engine_recall`'s output filenames
  at `recall_off.md` / `recall_on.md` / `recall_ab.md` and flips `signal_runner.DETECT_WIDE` at
  runtime before calling `t4_engine_recall.main()` for each arm — reuse it, do not rewrite the
  flag-flipping or the OFF/ON harness driver.
- Do not touch `signal_runner.py`. `DETECT_WIDE` stays exactly as 3.7 shipped it (module global,
  default `False`). This version does not arm it and does not change what ships.
- Denominators are unchanged from 3.7: 77 S / 60 A / 22 X, 159 marks, all with archived bars.
- Set `PYTHONIOENCODING=utf-8` before every Python run; the runner's console is cp1252 and a
  Unicode print kills a row silently.

## Tasks

### T1 -- Join-first recall, re-measured OFF vs ON

- model: glm

Rewrite the detection-counting path in `research/t4_engine_recall.py` (or a new
`research/t8_join_first_recall.py` that imports `run_day` from it, whichever keeps the change to
one clear location) so that, for each of the OFF and ON arms:

1. Run `run_day` for every marked symbol-day exactly as `t6_recall_ab.py` already does (do not
   change the replay itself, only what happens to its output).
2. For each mark, search `raw_sigs` directly for any entry within `+/-TOL` bars of `entry_i`,
   split into two counts: **any-grade** (any captured signal regardless of status) and
   **fired-only** (`status == "fired"`). This is the per-mark, join-first hit test. No
   `DEDUPE_BARS` window is applied before this step.
3. Track, across all marks, whether any single raw signal (identified by its `(symbol, day, bar,
   signal_type, direction)` tuple) satisfies more than one mark's join. Report the count if it is
   ever greater than zero; state "never happened" if it is zero. This is the only dedupe this row
   performs, and it happens strictly after the join.
4. Recompute fired S/A/X recall and any-signal S/A/X recall for both arms under this join-first
   method, over the same 77/60/22 denominators.

Write `research/recall_ab_v2.md`, structured to answer the verdict's open question directly:

- A section titled "Old method vs join-first" that puts 3.7's deduped-then-joined numbers
  (fired S 10/77 -> 14/77, any-signal S 27/77 -> 27/77, both from `research/recall_ab.md`) next
  to this row's join-first numbers, for both arms, side by side.
- State plainly which of T5's prediction (9 newly reachable S marks) or T6's headline (0 new S
  detections) the corrected number supports — or, if it lands somewhere between, say the exact
  count of newly-detected S marks the join-first method finds that the deduped method missed.
- Precision is **not** recomputed in this row — it depends on `entries` (the engine's actual
  trade list), not on this per-mark detection question, and 3.7's precision numbers (38.5% OFF,
  19.4% ON) stand. State this explicitly so nobody assumes precision moved.
- One paragraph on what this changes about arming `DETECT_WIDE`: per the 3.7 verdict, precision
  alone (19.4%, well short of viable) already rules it out regardless of the corrected recall
  number — state whether that conclusion holds or changes, but do not re-derive the precision
  argument, only reference it.

Do not modify `signal_runner.py`, do not change `DETECT_WIDE`'s default, and do not run
`backtest_12mo.py`.

- **done-when:** `research/recall_ab_v2.md` exists, contains a section comparing the old
  deduped-then-joined numbers against this row's join-first numbers for both arms over the same
  77/60/22 denominators, states explicitly which of T5's or T6's prior conclusion the corrected
  number supports (or the exact newly-detected count if neither fully holds), and states that
  precision is unchanged from `research/recall_ab.md` rather than silently omitting it.

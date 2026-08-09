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

**CARRY-FORWARD (audited 2026-08-09):** void, but T2's target — `research/marks_audit.md` — is still missing and has now been claimed done once (3.4 T3) and respecced once (here) without ever being written. Open in 3.9.

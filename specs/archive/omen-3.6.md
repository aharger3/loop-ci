# OMEN 3.6 - turn the 78 S trades into a gate the engine actually runs

status: done
version: omen-3.6
repo: aharger3/tradingbot
doc: Projects/OMEN.md

**CLOSED 2026-08-07.** Run `31122686346` was cancelled by GitHub Actions at 1h28m partway
through T7. T1-T6 completed and landed via PR #9, merged to `main` 2026-08-07; every artifact
their done-when names was independently verified present on `main` before this file was marked
done. **T7 is VOID** — a ~90-minute 12-month A/B of a gate whose own pre-registered keep-rate gap
is +12.5pp with a 95% CI of [-20.7, +45.5], run against an engine that fires on 4 of 77 of
Austin's S marks. It buys no decidable number. **T8's question is answered** in
`research/v36_verdict.md`, written from the six completed artifacts with nothing recomputed.
Successor: `specs/omen-3.7.md` — detection, not filtering.

target: fit a signal gate from Austin's own S/A/X verdicts, ship it into signal_runner.py as a
real flag, and A/B it on the 12-month backtest - so the answer is a new backtest number, not
another report.

**CARRY-FORWARD (audited 2026-08-09):** T7 never ran — `research/s_gate_ab.md` absent, so the S-gate shipped by T6 (`signal_runner.py:205`, `S_GATE = False`) has never been A/B'd. Open in 3.9. T8's verdict IS on main.

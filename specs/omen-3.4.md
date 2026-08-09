# OMEN 3.4 - level context as a filter

status: done
version: omen-3.4
repo: aharger3/tradingbot
doc: Projects/omen-trading.md

> **Closed 2026-08-06.** T9's verdict was produced twice (runs `31059153572`/`31067635239`) but
> both PRs on `tradingbot` sat unmerged for a day, so this spec kept re-selecting on every
> future push. Recovered, reconciled, merged as `tradingbot#6` (`research/v34_verdict.md`).
> Verdict: NOT-YET-MEASURABLE, one code fix identified (`levels.py` HOD/LOD off-by-one). See
> `omen-3.5.md` for the follow-on. Full writeup: vault `Projects/omen-v3-results.md` §8.

target: decide whether higher-timeframe level context earns a place in OMEN, by measuring it against the trade population that already exists on disk - and by learning Austin's real target rule from his marks instead of asking him again.

**CARRY-FORWARD (audited 2026-08-09):** T3's `[x]` was false — `research/marks_audit.md` was never written. Re-specced as omen-3.5 T2, which also never ran. Open in 3.9.

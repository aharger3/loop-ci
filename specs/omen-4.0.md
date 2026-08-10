# OMEN 4.0 - taxonomy short-circuit fix + 29-mark regrade + SPCX

status: ready
version: omen-4.0
repo: aharger3/tradingbot
doc: Projects/OMEN.md

target: fix the miss-taxonomy short-circuit that has hidden the One Candle Rule from
every `no_break_retest` mark since 3.7, merge Austin's 29-mark regrade (13 new S),
add SPCX to data_archive, and recompute S-grade recall/precision on the corrected corpus.

<!-- `doc:` points at Projects/OMEN.md — confirmed exists on main, this run's summary
     writes there. -->

### T1 -- merge the 29-mark regrade into the corpus
- model: deepseek

Austin re-graded all 29 marks from the `no_break_retest` FSM buckets (`seek_retest`,
`seek_leave`, `seek_break`) via the omen-3.9-homework §3 cards. Write the JSON array
below verbatim to `research/mark_batch_03_regrades.jsonl` (one JSON object per line,
not a JSON array file — convert accordingly). Then load `research/austin_marks_v3.jsonl`
(the 184-row corpus from 3.9 T3) and for each of these 29 `id`s: if the id already
exists in the corpus, overwrite its `austin_tier` and `setup` fields with the new
values (and `note` if present); if it does not exist, append it as a new row with the
same schema as existing rows (symbol, day, entry_i/bar, tod, austin_tier, setup, note).
Write the result to `research/austin_marks_v4.jsonl`. Do not touch any row not in this
list of 29 ids.

```json
[
 {"id":"BABA_2025-07-22_20","bucket":"seek_retest","symbol":"BABA","day":"2025-07-22","entry_i":20,"tod":"09:50","tier":"S","setup":"OCR"},
 {"id":"IWM_2024-02-28_9","bucket":"seek_retest","symbol":"IWM","day":"2024-02-28","entry_i":9,"tod":"09:39","tier":"S","setup":"OCR"},
 {"id":"IWM_2026-05-28_46","bucket":"seek_retest","symbol":"IWM","day":"2026-05-28","entry_i":46,"tod":"10:16","setup":"BR","tier":"S"},
 {"id":"IWM_2026-07-24_29","bucket":"seek_retest","symbol":"IWM","day":"2026-07-24","entry_i":29,"tod":"09:59","tier":"A","note":"never broke that PML earlier","setup":"OCR"},
 {"id":"ORCL_2025-03-28_12","bucket":"seek_retest","symbol":"ORCL","day":"2025-03-28","entry_i":12,"tod":"09:42","tier":"A","note":"here to be s you draw a trend link would like a second confirmation candle with strength to break that line","setup":"OCR"},
 {"id":"QQQ_2025-02-26_28","bucket":"seek_retest","symbol":"QQQ","day":"2025-02-26","entry_i":28,"tod":"09:58","tier":"S","setup":"OCR"},
 {"id":"QQQ_2025-03-17_16","bucket":"seek_retest","symbol":"QQQ","day":"2025-03-17","entry_i":16,"tod":"09:46","tier":"S","setup":"OCR"},
 {"id":"QQQ_2025-03-18_13","bucket":"seek_retest","symbol":"QQQ","day":"2025-03-18","entry_i":13,"tod":"09:43","tier":"A","setup":"OCR"},
 {"id":"QQQ_2026-02-11_32","bucket":"seek_retest","symbol":"QQQ","day":"2026-02-11","entry_i":32,"tod":"10:02","tier":"X","setup":"none"},
 {"id":"QQQ_2026-02-11_45","bucket":"seek_retest","symbol":"QQQ","day":"2026-02-11","entry_i":45,"tod":"10:15","tier":"A","note":"little overextended the stock, and didn't get past pml","setup":"BR"},
 {"id":"QQQ_2026-07-09_11","bucket":"seek_retest","symbol":"QQQ","day":"2026-07-09","entry_i":11,"tod":"09:41","tier":"S","setup":"OCR"},
 {"id":"SPY_2024-06-11_23","bucket":"seek_retest","symbol":"SPY","day":"2024-06-11","entry_i":23,"tod":"09:53","tier":"X","setup":"none","note":"dont see any levels, unless some were forgot to be marked"},
 {"id":"SPY_2024-09-19_19","bucket":"seek_retest","symbol":"SPY","day":"2024-09-19","entry_i":19,"tod":"09:49","setup":"none","tier":"X","note":"doesn't approach any one candle rule or pivot or level for retest"},
 {"id":"SPY_2025-03-18_13","bucket":"seek_retest","symbol":"SPY","day":"2025-03-18","entry_i":13,"tod":"09:43","tier":"S","setup":"OCR"},
 {"id":"SPY_2026-03-02_24","bucket":"seek_retest","symbol":"SPY","day":"2026-03-02","entry_i":24,"tod":"09:54","setup":"BR","tier":"A","note":"candles look a little choppier wicks on both sides"},
 {"id":"SPY_2026-03-03_17","bucket":"seek_retest","symbol":"SPY","day":"2026-03-03","entry_i":17,"tod":"09:47","tier":"S","setup":"BR"},
 {"id":"UBER_2026-07-06_12","bucket":"seek_retest","symbol":"UBER","day":"2026-07-06","entry_i":12,"tod":"09:42","tier":"S","setup":"OCR"},
 {"id":"AMD_2025-06-05_6","bucket":"seek_leave","symbol":"AMD","day":"2025-06-05","entry_i":6,"tod":"09:36","tier":"S","setup":"OCR"},
 {"id":"IWM_2025-10-21_9","bucket":"seek_leave","symbol":"IWM","day":"2025-10-21","entry_i":9,"tod":"09:39","note":"1 candle earlier is the entry, marking A because 4 candles before the mark is a bullish candle and price never got close below those levels, so it looks riskier not knowing if it's gonna run","tier":"A","setup":"OCR"},
 {"id":"MU_2026-01-28_13","bucket":"seek_leave","symbol":"MU","day":"2026-01-28","entry_i":13,"tod":"09:43","tier":"X","setup":"none"},
 {"id":"NVDA_2024-11-18_10","bucket":"seek_leave","symbol":"NVDA","day":"2024-11-18","entry_i":10,"tod":"09:40","tier":"C","note":"6 candles earlier is a break and retest no displacement, so that would've been A and this one C","setup":"OCR"},
 {"id":"QQQ_2024-05-08_8","bucket":"seek_leave","symbol":"QQQ","day":"2024-05-08","entry_i":8,"tod":"09:38","tier":"A","note":"no displacement","setup":"OCR"},
 {"id":"SPY_2024-04-03_9","bucket":"seek_leave","symbol":"SPY","day":"2024-04-03","entry_i":9,"tod":"09:39","tier":"A","note":"candle after is your entry because nothing touched, stop is bottom of red order block","setup":"OCR"},
 {"id":"IWM_2024-04-03_13","bucket":"seek_break","symbol":"IWM","day":"2024-04-03","entry_i":13,"tod":"09:43","setup":"OCR","tier":"S","note":"large wick before candle entry gives confidence even though it's not the absolute strongest green candle"},
 {"id":"IWM_2024-04-03_73","bucket":"seek_break","symbol":"IWM","day":"2024-04-03","entry_i":73,"tod":"10:43","setup":"OCR","tier":"S","note":"candle before is the entry actually, because it's enough strength and only taps into the wick of the order block"},
 {"id":"MSFT_2025-03-20_28","bucket":"seek_break","symbol":"MSFT","day":"2025-03-20","entry_i":28,"tod":"09:58","tier":"A","note":"too much consolidation before entry and the candle before entry is where you would've liked to see strength","setup":"BR"},
 {"id":"PLTR_2025-09-18_14","bucket":"seek_break","symbol":"PLTR","day":"2025-09-18","entry_i":14,"tod":"09:44","setup":"BR","tier":"S"},
 {"id":"QQQ_2024-01-04_41","bucket":"seek_break","symbol":"QQQ","day":"2024-01-04","entry_i":41,"tod":"10:11","tier":"C","note":"4 candles earlier is an A trade (break and retest no displacement); this one has good price action but lower probability because of the earlier almost-setup. Changed mind slightly: this = C, earlier entry = A","setup":"OCR"},
 {"id":"QQQ_2024-12-16_28","bucket":"seek_break","symbol":"QQQ","day":"2024-12-16","entry_i":28,"tod":"09:58","tier":"C","note":"same as previous — break and retest no displacement entry 7 candles before, price action good on this mark but lower probability because of the earlier looking setup. Changed mind slightly: this = C, earlier entry = A","setup":"BR"}
]
```

- **done-when:** `research/austin_marks_v4.jsonl` exists, has >=184 rows, and all 29 ids
  above resolve to the tier/setup values given.
- **verify:**
  ```bash
  test -f research/mark_batch_03_regrades.jsonl
  python - <<'PY'
import json
rows=[json.loads(l) for l in open('research/austin_marks_v4.jsonl')]
assert len(rows) >= 184, f"only {len(rows)} rows"
regrades={json.loads(l)['id']:json.loads(l) for l in open('research/mark_batch_03_regrades.jsonl')}
byid={}
for r in rows:
    rid = r.get('id') or f"{r['symbol']}_{r['day']}_{r.get('entry_i', r.get('bar'))}"
    byid[rid]=r
missing=[i for i in regrades if i not in byid]
assert not missing, f"missing ids: {missing}"
mismatched=[i for i,g in regrades.items() if byid[i].get('austin_tier') != g['tier']]
assert not mismatched, f"tier mismatch: {mismatched}"
print("OK", len(rows), "rows,", len(regrades), "regrades verified")
PY
  ```

### T2 -- fix the no_break_retest taxonomy short-circuit
- model: glm

`research/miss_autopsy.py:120` returns the reason `no_break_retest` the instant
`detect_break_retest` is falsy for every level, before `detect_order_block_setup` is
ever called on that bar. This is the structural defect flagged in `Projects/OMEN.md`
("There is no S in the engine" section, defect #1) and it is why the One Candle Rule
was invisible on all 29 marks Austin just regraded — 15 of those 29 turned out to be
OCR or BR setups the classifier never checked for.

Fix: at the point where `detect_break_retest` returns falsy for every level and the
code is about to assign `no_break_retest`, call `detect_order_block_setup` on the same
bar/level window first. If it returns a hit, assign reason `one_candle_rule_missed`
(new reason string) instead of `no_break_retest`. Only fall through to
`no_break_retest` if `detect_order_block_setup` also returns nothing. Add
`one_candle_rule_missed` to `REASON_SET`. Do not change `detect_break_retest` or
`detect_order_block_setup` themselves — only the ordering/short-circuit in
`miss_autopsy.py`.

- **done-when:** `no_break_retest` is only assigned after both detectors are checked;
  `one_candle_rule_missed` exists in `REASON_SET` and appears in a re-run of the miss
  autopsy over the 29 regraded marks' symbol-days.
- **verify:**
  ```bash
  grep -q "one_candle_rule_missed" research/miss_autopsy.py
  python -c "
import ast,sys
src = open('research/miss_autopsy.py').read()
assert 'detect_order_block_setup' in src.split('no_break_retest')[0] or 'one_candle_rule_missed' in src, 'short-circuit not fixed'
print('OK')
"
  python -m pytest tests/ -k miss_autopsy -q || python research/miss_autopsy.py --smoke
  ```

### T3 -- add SPCX to data_archive
- model: deepseek

Austin's call: add SPCX only, skip HTZ (hype-boosted, not expected to hold top-14
options volume). Fetch and bank 1-minute historical bars for SPCX into
`data_archive/` using the same ingestion path the other 13 equity_pool symbols use
(check `research/priority_pool.json` and whatever script populated the existing
`data_archive/` files for NVDA/TSLA/etc. — likely under `scripts/` or `data/`). Do
not touch HTZ or MSTR.

- **done-when:** `data_archive/` has SPCX bar coverage the same shape as an existing
  equity_pool symbol (e.g. same date range granularity as PLTR).
- **verify:**
  ```bash
  python -c "
import glob
spcx = glob.glob('data_archive/**/SPCX*', recursive=True) + glob.glob('data_archive/SPCX*')
assert spcx, 'no SPCX data_archive coverage found'
print('OK', len(spcx), 'SPCX files')
"
  ```

### T4 -- recompute S-grade recall/precision on the corrected corpus
- model: glm
- depends-on: T1, T2

Re-run the recall/precision measure (the same one that produced 3.9's
`research/v39_verdict.md`) using `research/austin_marks_v4.jsonl` (T1) and the
patched `research/miss_autopsy.py` (T2). Report per-pool (equity_pool / index_pool)
S-grade fired recall and precision, same table shape as `v39_verdict.md`. Write to
`research/v40_verdict.md`. Do not change `TRADE_S_ONLY` or any live trading gate —
this version measures, it does not arm anything.

- **done-when:** `research/v40_verdict.md` contains a line
  `s_grade_fired_recall:` with a fraction, and it differs from 3.9's `12/77`
  baseline (either direction — the point is it's recomputed, not asserted flat).
- **verify:**
  ```bash
  test -f research/v40_verdict.md
  grep -q "s_grade_fired_recall:" research/v40_verdict.md
  grep -qE "equity_pool" research/v40_verdict.md
  grep -qE "index_pool" research/v40_verdict.md
  python research/regression_gate.py
  ```

### T5 -- walk-forward / out-of-sample re-run in plain English
- model: deepseek
- depends-on: T4

3.9's `t8_verdict_measure.py` dollar figures (+$54k on 591 S-only trades) are
in-sample over the full archive — the same history used to build the rules is the
history used to grade them, which inflates the numbers. Re-run
`t8_verdict_measure.py` (or the T4 equivalent) walk-forward: split the archive into
chronological folds (e.g. first 70% of trading days as the "known" period, last 30%
as "unseen"), and report the S-only recall/precision/R on the unseen fold only.

Write `research/v40_walkforward.md` with a short plain-English paragraph (no code
terms, no jargon) explaining: what walk-forward testing means, why in-sample numbers
overstate performance, and what the out-of-sample S-only numbers actually came out to
compared to the in-sample ones.

- **done-when:** `research/v40_walkforward.md` exists, is readable by someone who
  doesn't code, and states both the in-sample and out-of-sample S-only R/precision
  numbers side by side.
- **verify:**
  ```bash
  test -s research/v40_walkforward.md
  grep -qi "out.of.sample" research/v40_walkforward.md
  grep -qi "in.sample" research/v40_walkforward.md
  ```

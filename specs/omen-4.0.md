# OMEN 4.0 - correct the corpus and the two live bugs

status: ready
version: omen-4.0
repo: aharger3/tradingbot
doc: Projects/OMEN.md

target: get the label corpus and the engine honest before measuring anything — merge two
grading batches (29 regrades + 35 blind cards), mine 14 more marks out of Austin's own
notes, fix the taxonomy short-circuit that hides the One Candle Rule, enforce the
settled no-repeat-entries rule that the engine is visibly violating, expand the archive,
and build the churn report. **4.0 measures nothing** — every recall/precision/walk-forward
number is omen-4.1, computed once on a corrected base instead of twice on a wrong one.

<!-- `doc:` points at Projects/OMEN.md — confirmed on main; this run's summary writes there. -->

### [x] T1 -- merge the 29-mark regrade into the corpus
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

### [x] T2 -- fix the no_break_retest taxonomy short-circuit
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

### [x] T3 -- add SPCX and widen the archive date range
- model: deepseek

Two jobs, one ingestion path.

**(a) SPCX.** Austin's call: SPCX only, skip HTZ (hype-boosted, not expected to hold
top-14 options volume). Fetch and bank 1-minute historical bars for SPCX into
`data_archive/` using the same ingestion path the other 13 equity_pool symbols use
(check `research/priority_pool.json` and whatever script populated the existing
`data_archive/` files for NVDA/TSLA/etc. — likely under `scripts/` or `data/`). Do
not touch HTZ or MSTR.

**(b) Widen coverage.** Austin's complaint is that every backtest looks the same run
after run. Part of that is that the archive has not grown since 3.6. Determine the
current per-symbol date coverage in `data_archive/`, then extend every equity_pool and
index_pool symbol forward to the most recent available trading day and backward to a
common start date shared by the whole pool. Write `research/t3_archive_coverage.md`
with a table: symbol, old first day, old last day, new first day, new last day,
new symbol-days added. Do not delete or rewrite existing bar files — append only.

- **done-when:** `data_archive/` has SPCX bar coverage the same shape as an existing
  equity_pool symbol, and `research/t3_archive_coverage.md` reports a total
  `symbol_days_added:` count greater than zero.
- **verify:**
  ```bash
  python -c "
import glob
spcx = glob.glob('data_archive/**/SPCX*', recursive=True) + glob.glob('data_archive/SPCX*')
assert spcx, 'no SPCX data_archive coverage found'
print('OK', len(spcx), 'SPCX files')
"
  test -s research/t3_archive_coverage.md
  grep -q "symbol_days_added:" research/t3_archive_coverage.md
  python -c "
import re
m=re.search(r'symbol_days_added:\s*(\d+)', open('research/t3_archive_coverage.md').read())
assert m and int(m.group(1))>0, 'symbol_days_added must be > 0'
print('OK', m.group(1), 'symbol-days added')
"
  ```

### [x] T4 -- merge the 35-card blind batch
- model: deepseek
- depends-on: T1

Austin graded 35 cards on 2026-08-10: 30 never-before-graded `equity_pool` engine
fires (Batch A), 4 `timing_miss` confirms (Batch B), 1 OCR re-check (Batch C).
**This is the first blind sample of what the engine actually does on equities and the
result is 1 S out of 30.** Do not soften or re-interpret any grade.

Write the JSON array below verbatim to `research/mark_batch_04_grades.jsonl` (one JSON
object per line). Then load `research/austin_marks_v4.jsonl` (T1's output) and merge:
for each id, overwrite `austin_tier` / `setup` / `note` if the id exists, else append a
new row using the same schema as existing rows. The `id` format is
`SYMBOL_YYYY-MM-DD_ENTRYI`; derive `symbol`, `day`, `entry_i` by splitting it, and set
`tod` as the clock time of that bar assuming `entry_i` is minutes elapsed from 09:30 ET
(entry_i 13 -> 09:43; this convention is confirmed against every row of
`mark_batch_03_regrades.jsonl`). Map the card's `tier` field to `austin_tier`. Write the
result to `research/austin_marks_v5.jsonl`.

```json
[
 {"id":"AMD_2026-05-14_17","setup":"none","tier":"X","note":"later s entry 8 candles later OCR"},
 {"id":"AMD_2026-05-14_43","setup":"OCR","tier":"C","note":"earlier s entry, this one took longer to develop, 2 candles earlier is entry"},
 {"id":"AMD_2026-05-14_67","setup":"84","tier":"A","note":"two candles earlier is your s entry because its a reclaim of the earlier entry, I count it as A because you were a little late and took longer to develop"},
 {"id":"AMZN_2026-04-10_10","setup":"none","tier":"X","note":""},
 {"id":"AMZN_2026-07-17_34","setup":"BR","tier":"C","note":"pivot structure break stronger then level break, earlier entry hold of one candle rule 12 bars earlier"},
 {"id":"GOOGL_2024-10-15_24","setup":"none","tier":"X","note":""},
 {"id":"GOOGL_2024-10-15_47","setup":"none","tier":"X","note":"2 earlier entry opportunities that were S, first one 9:43, second 10:02"},
 {"id":"GOOGL_2025-08-07_62","setup":"none","tier":"X","note":""},
 {"id":"INTC_2025-06-05_22","setup":"BR","tier":"X","note":"on candle earlier is your entry and then it would've been A, because earlier trade opportunity of OCR was at 9:45 as candle forming not all the way at LOD"},
 {"id":"META_2025-09-23_74","setup":"none","tier":"X","note":"late in day, not above key levels, slow mover"},
 {"id":"MSFT_2026-02-11_6","setup":"none","tier":"X","note":""},
 {"id":"MSFT_2026-02-11_9","setup":"none","tier":"X","note":""},
 {"id":"MU_2026-01-28_10","setup":"none","tier":"X","note":"earlier S entry 9:35 OCR perfect setup"},
 {"id":"MU_2026-01-28_71","setup":"none","tier":"X","note":"s trades come early, sometime a and c can fire later, this is nothing"},
 {"id":"NVDA_2024-11-18_66","setup":"none","tier":"X","note":""},
 {"id":"NVDA_2024-12-16_7","setup":"none","tier":"X","note":""},
 {"id":"NVDA_2024-12-16_14","setup":"none","tier":"X","note":"your trade never, two candles earlier is your S entry OCR and BR confluence"},
 {"id":"NVDA_2024-12-16_76","setup":"none","tier":"X","note":""},
 {"id":"PLTR_2024-10-23_10","setup":"none","tier":"X","note":"wick not touching a level, later entry 9:51 OCR, S trade"},
 {"id":"PLTR_2024-10-23_50","setup":"none","tier":"X","note":""},
 {"id":"PLTR_2025-09-18_5","setup":"none","tier":"X","note":""},
 {"id":"PLTR_2025-09-18_28","setup":"none","tier":"X","note":""},
 {"id":"TSLA_2024-01-12_27","setup":"none","tier":"X","note":""},
 {"id":"TSLA_2024-02-05_8","setup":"none","tier":"X","note":""},
 {"id":"TSLA_2024-02-05_10","setup":"none","tier":"X","note":""},
 {"id":"TSLA_2024-03-27_9","setup":"BR","tier":"S","note":""},
 {"id":"TSLA_2024-03-27_10","setup":"none","tier":"X","note":""},
 {"id":"TSLA_2024-03-27_85","setup":"none","tier":"X","note":""},
 {"id":"TSLA_2024-06-24_14","setup":"none","tier":"X","note":"too choppy no displacement"},
 {"id":"TSLA_2024-12-03_17","setup":"BR","tier":"C","note":"break and retest of not a large pivot structure just two candles and no displacement"},
 {"id":"COIN_2025-10-21_8","setup":"OCR","tier":"S","note":"my mark is a better entry by far yes and s quality. blue line entry is C because between tight levels and a consolidation pivot it would have to break for low of day, and red mark is a c as well"},
 {"id":"MARA_2024-12-17_49","setup":"BR","tier":"S","note":"as candle is forming on my entry yes, stop out and 84 percent rule, your entries x"},
 {"id":"ORCL_2025-11-03_17","setup":"OCR","tier":"A","note":"my entry s criteria but late entry, because earlier one existed with less displacement"},
 {"id":"TSLA_2024-06-24_9","setup":"BR","tier":"A","note":"large upper wick to target didn't materialize no displacement, your red mark is a c trade and the blue mark is an x trade"},
 {"id":"SPY_2025-03-18_13","setup":"OCR","tier":"S","note":""}
]
```

Then write `research/t4_batch04_summary.md` containing, computed from the file you just
wrote (not copied from this prose):

```
batch_a_n: 30
batch_a_S: <count>
batch_a_A: <count>
batch_a_C: <count>
batch_a_X: <count>
blind_equity_S_precision: <batch_a_S>/30
corpus_rows_v5: <row count of austin_marks_v5.jsonl>
```

- **done-when:** `research/austin_marks_v5.jsonl` exists, every one of the 35 ids
  resolves to the tier given above, and `research/t4_batch04_summary.md` reports
  `batch_a_S: 1` and `blind_equity_S_precision: 1/30`.
- **verify:**
  ```bash
  test -f research/mark_batch_04_grades.jsonl
  grep -q "blind_equity_S_precision: 1/30" research/t4_batch04_summary.md
  grep -q "batch_a_S: 1" research/t4_batch04_summary.md
  python - <<'PY'
import json
rows=[json.loads(l) for l in open('research/austin_marks_v5.jsonl')]
b4={json.loads(l)['id']:json.loads(l) for l in open('research/mark_batch_04_grades.jsonl')}
assert len(b4)==35, f"batch_04 has {len(b4)} ids, expected 35"
byid={}
for r in rows:
    rid = r.get('id') or f"{r['symbol']}_{r['day']}_{r.get('entry_i', r.get('bar'))}"
    byid[rid]=r
missing=[i for i in b4 if i not in byid]
assert not missing, f"missing ids: {missing}"
bad=[i for i,g in b4.items() if byid[i].get('austin_tier')!=g['tier']]
assert not bad, f"tier mismatch: {bad}"
assert len(rows) >= 184, f"corpus shrank to {len(rows)}"
print("OK", len(rows), "rows, 35 batch_04 ids verified")
PY
  ```

### [x] T5 -- mine the 14 marks Austin named inside his own notes
- model: deepseek
- depends-on: T4

Most X cards in batch 04 say where the *real* trade was — "earlier S entry 9:35 OCR",
"2 candles earlier is your S entry", "9:43 and 10:02". Those are labels the corpus has
never held. The bar index is mechanical: `entry_i` is minutes elapsed from 09:30 ET, so
a clock time of 09:43 is `entry_i` 13, and "2 candles earlier" than `entry_i` 43 is 41.
**The derivations below are already done — write them, do not re-derive from the note
text.**

Write this array verbatim to `research/derived_marks_v1.jsonl` (one object per line),
then merge into `research/austin_marks_v5.jsonl` (T4's output) using the same
append/overwrite logic as T4, carrying the `derived: true` flag onto every merged row so
a later run can split them out. Write the result to `research/austin_marks_v6.jsonl`.

```json
[
 {"id":"AMD_2026-05-14_25","symbol":"AMD","day":"2026-05-14","entry_i":25,"tod":"09:55","tier":"S","setup":"OCR","derived":true,"source_id":"AMD_2026-05-14_17","source_phrase":"later s entry 8 candles later OCR"},
 {"id":"AMD_2026-05-14_41","symbol":"AMD","day":"2026-05-14","entry_i":41,"tod":"10:11","tier":"S","setup":"OCR","derived":true,"source_id":"AMD_2026-05-14_43","source_phrase":"earlier s entry, 2 candles earlier is entry"},
 {"id":"AMD_2026-05-14_65","symbol":"AMD","day":"2026-05-14","entry_i":65,"tod":"10:35","tier":"S","setup":"84","derived":true,"source_id":"AMD_2026-05-14_67","source_phrase":"two candles earlier is your s entry because its a reclaim of the earlier entry"},
 {"id":"GOOGL_2024-10-15_13","symbol":"GOOGL","day":"2024-10-15","entry_i":13,"tod":"09:43","tier":"S","setup":"unknown","derived":true,"source_id":"GOOGL_2024-10-15_47","source_phrase":"2 earlier entry opportunities that were S, first one 9:43"},
 {"id":"GOOGL_2024-10-15_32","symbol":"GOOGL","day":"2024-10-15","entry_i":32,"tod":"10:02","tier":"S","setup":"unknown","derived":true,"source_id":"GOOGL_2024-10-15_47","source_phrase":"second 10:02"},
 {"id":"INTC_2025-06-05_21","symbol":"INTC","day":"2025-06-05","entry_i":21,"tod":"09:51","tier":"A","setup":"BR","derived":true,"source_id":"INTC_2025-06-05_22","source_phrase":"on candle earlier is your entry and then it would've been A"},
 {"id":"MU_2026-01-28_5","symbol":"MU","day":"2026-01-28","entry_i":5,"tod":"09:35","tier":"S","setup":"OCR","derived":true,"source_id":"MU_2026-01-28_10","source_phrase":"earlier S entry 9:35 OCR perfect setup"},
 {"id":"NVDA_2024-12-16_12","symbol":"NVDA","day":"2024-12-16","entry_i":12,"tod":"09:42","tier":"S","setup":"OCR","derived":true,"source_id":"NVDA_2024-12-16_14","source_phrase":"two candles earlier is your S entry OCR and BR confluence"},
 {"id":"PLTR_2024-10-23_21","symbol":"PLTR","day":"2024-10-23","entry_i":21,"tod":"09:51","tier":"S","setup":"OCR","derived":true,"source_id":"PLTR_2024-10-23_10","source_phrase":"later entry 9:51 OCR, S trade"},
 {"id":"COIN_2025-10-21_23","symbol":"COIN","day":"2025-10-21","entry_i":23,"tod":"09:53","tier":"C","setup":"unknown","derived":true,"source_id":"COIN_2025-10-21_8","source_phrase":"blue line entry is C"},
 {"id":"COIN_2025-10-21_31","symbol":"COIN","day":"2025-10-21","entry_i":31,"tod":"10:01","tier":"C","setup":"unknown","derived":true,"source_id":"COIN_2025-10-21_8","source_phrase":"red mark is a c as well"},
 {"id":"MARA_2024-12-17_76","symbol":"MARA","day":"2024-12-17","entry_i":76,"tod":"10:46","tier":"X","setup":"none","derived":true,"source_id":"MARA_2024-12-17_49","source_phrase":"your entries x"},
 {"id":"MARA_2024-12-17_78","symbol":"MARA","day":"2024-12-17","entry_i":78,"tod":"10:48","tier":"X","setup":"none","derived":true,"source_id":"MARA_2024-12-17_49","source_phrase":"your entries x"},
 {"id":"TSLA_2024-06-24_13","symbol":"TSLA","day":"2024-06-24","entry_i":13,"tod":"09:43","tier":"X","setup":"none","derived":true,"source_id":"TSLA_2024-06-24_9","source_phrase":"the blue mark is an x trade"}
]
```

Three more entries are named in notes but **carry no stated tier**, so they are not
labels. Write them to `research/derived_unconfirmed_v1.jsonl` with `tier: null` and do
**not** merge them into the corpus — they become a future confirm deck:

```json
[
 {"id":"AMZN_2026-07-17_22","symbol":"AMZN","day":"2026-07-17","entry_i":22,"tod":"09:52","tier":null,"setup":"OCR","source_id":"AMZN_2026-07-17_34","source_phrase":"earlier entry hold of one candle rule 12 bars earlier"},
 {"id":"INTC_2025-06-05_15","symbol":"INTC","day":"2025-06-05","entry_i":15,"tod":"09:45","tier":null,"setup":"OCR","source_id":"INTC_2025-06-05_22","source_phrase":"earlier trade opportunity of OCR was at 9:45 as candle forming not all the way at LOD"},
 {"id":"ORCL_2025-11-03_25","symbol":"ORCL","day":"2025-11-03","entry_i":25,"tod":"09:55","tier":null,"setup":"unknown","source_id":"ORCL_2025-11-03_17","source_phrase":"earlier one existed with less displacement"}
]
```

One conflict to record, not resolve: `TSLA_2024-06-24_14` was graded **X** on its own
batch-04 card ("too choppy no displacement") but the note on `TSLA_2024-06-24_9` calls
the same bar ("your red mark") a **C**. The direct card grade wins — keep X. Append a
`## Conflicts` section naming this to `research/t5_derived_marks.md`.

Also write `research/t5_derived_marks.md` with a table of every derived row (id, source
id, tier, setup, the phrase it came from) and these lines computed from the files:

```
derived_marks_merged: <count>
derived_S_added: <count of tier S among derived>
corpus_rows_v6: <row count>
```

- **done-when:** `research/austin_marks_v6.jsonl` exists with 14 more rows than v5, every
  derived row carries `derived: true`, the 3 unconfirmed rows are in their own file and
  *not* in the corpus, and `t5_derived_marks.md` reports `derived_S_added: 7`.
- **verify:**
  ```bash
  test -s research/t5_derived_marks.md
  grep -q "derived_marks_merged: 14" research/t5_derived_marks.md
  grep -q "derived_S_added: 7" research/t5_derived_marks.md
  grep -qi "Conflicts" research/t5_derived_marks.md
  python - <<'PY'
import json
v5=[json.loads(l) for l in open('research/austin_marks_v5.jsonl')]
v6=[json.loads(l) for l in open('research/austin_marks_v6.jsonl')]
assert len(v6)-len(v5)==14, f"v6-v5 = {len(v6)-len(v5)}, expected 14"
d=[r for r in v6 if r.get('derived')]
assert len(d)==14, f"{len(d)} rows flagged derived, expected 14"
assert sum(1 for r in d if r.get('austin_tier')=='S')==7, "expected 7 derived S marks"
unc={json.loads(l)['id'] for l in open('research/derived_unconfirmed_v1.jsonl')}
assert len(unc)==3, f"{len(unc)} unconfirmed, expected 3"
ids={r.get('id') for r in v6}
leaked=unc & ids
assert not leaked, f"unconfirmed rows leaked into corpus: {leaked}"
print("OK v6 =", len(v6), "rows, 14 derived, 3 held back")
PY
  ```

### [x] T6 -- enforce no-repeat entries in the engine
- model: glm

Austin settled this on 2026-08-09 and it is written in `Projects/OMEN.md` but was never
put in the code, and batch 04 shows the engine violating it constantly: TSLA 2024-03-27
fired bars **9 (S) and 10 (X)** — adjacent; MSFT 2026-02-11 fired 6 and 9; NVDA
2024-12-16 fired 7, 14 and 76; TSLA 2024-02-05 fired 8 and 10. Every duplicate after the
first is an X. This is the single largest source of the 3% blind equity precision.

The settled rule, verbatim: **no repeat entries — take the first one available.** Scope
is **symbol + direction + level**. Once an S fires long off PDH on TSLA, no second long
off PDH that day. A different level, or the other direction, is a different idea and may
fire. The **only** exception is an armed 84% re-entry (`RULE84`), which is by definition
a second entry on the same idea and must remain allowed.

Implement in `signal_runner.py`: keep a per-session set keyed by
`(symbol, direction, level_id)` — use whatever identity the level object already carries;
if levels have no stable id, key on the rounded level price to a sensible tick. Suppress
any signal whose key is already in the set. Do not suppress when the signal is flagged as
an 84% re-entry. Gate the whole behaviour behind a config flag `NO_REPEAT_ENTRIES`
defaulting to **True**, so a backtest can measure both arms.

Write `research/t6_no_repeat.md` reporting, over the existing archive, a before/after:
total signals fired with the flag off vs on, and the count of suppressed duplicates
broken out per pool. Include these exact lines:

```
signals_flag_off: <n>
signals_flag_on: <n>
duplicates_suppressed: <n>
```

- **done-when:** `NO_REPEAT_ENTRIES` exists in the engine defaulting True, an armed 84%
  re-entry is exempt from suppression, and `t6_no_repeat.md` shows
  `duplicates_suppressed` greater than zero with `signals_flag_on` < `signals_flag_off`.
- **verify:**
  ```bash
  grep -q "NO_REPEAT_ENTRIES" signal_runner.py
  test -s research/t6_no_repeat.md
  python - <<'PY'
import re
t=open('research/t6_no_repeat.md').read()
off=int(re.search(r'signals_flag_off:\s*(\d+)',t).group(1))
on=int(re.search(r'signals_flag_on:\s*(\d+)',t).group(1))
dup=int(re.search(r'duplicates_suppressed:\s*(\d+)',t).group(1))
assert dup>0, "no duplicates suppressed - rule is not doing anything"
assert on<off, f"flag_on {on} not less than flag_off {off}"
print("OK", off, "->", on, f"({dup} suppressed)")
PY
  python -m pytest tests/ -q -x || true
  python research/regression_gate.py
  ```

### T7 -- build the backtest churn report
- model: deepseek

Austin's read is that every backtest since 3.6 looks the same and he cannot tell whether
a version changed anything or whether the same trades keep coming back. Make that
visible permanently.

Build `research/backtest_churn.py`. It takes two backtest trade sets (the current run and
a stored previous snapshot) and reports the diff by trade identity
(`symbol + day + entry bar + direction`):

- `trades_added` — in current, not in previous
- `trades_dropped` — in previous, not in current
- `trades_unchanged` — in both, same grade
- `trades_regraded` — in both, grade changed (name the from->to)

Then snapshot the current backtest trade set to `research/churn_baseline_v40.json` so
4.1 has something to diff against, and write `research/t7_churn.md` with the four counts
plus a per-pool split. Running it with the baseline against itself must report all
unchanged and zero added/dropped — include that as a self-test in the script
(`--selftest`).

- **done-when:** `backtest_churn.py` exists, `--selftest` exits 0, the baseline snapshot
  file exists and is non-empty, and `t7_churn.md` carries all four counts.
- **verify:**
  ```bash
  test -s research/backtest_churn.py
  python research/backtest_churn.py --selftest
  test -s research/churn_baseline_v40.json
  grep -q "trades_added:" research/t7_churn.md
  grep -q "trades_dropped:" research/t7_churn.md
  grep -q "trades_unchanged:" research/t7_churn.md
  grep -q "trades_regraded:" research/t7_churn.md
  ```

### [x] T8 -- find the 84% re-entry candidates the card deck can never show
- model: glm
- depends-on: T5

The 84% rule appears once in 35 graded cards, and that is a tool defect, not a gap in
Austin's understanding. By its own settled definition it is a **re-entry after a loser**:
it arms only when a break-and-retest or One Candle Rule entry stops out, then triggers
when a candle closes at or above the price originally entered. A single-bar grading card
physically cannot show that — it needs the losing entry, the stop-out, and the reclaim.
So no deck has ever asked him about it, and no artifact has ever reported it.

Scan the archive for the pattern and produce the candidate set:

1. For every BR or OCR entry the engine would take (grades included, not S-only), simulate
   forward to a stop-out at the entry's own stop.
2. From the stop-out bar forward, find the first bar that **closes at or above the
   original entry price** (mirror for shorts) within the same session.
3. Record: symbol, day, original entry bar, stop-out bar, reclaim bar, original entry
   price, reclaim close, and what the re-entry would have returned in R had it been taken
   with the original stop.

Write `research/rule84_candidates.jsonl` (one candidate per line) and
`research/t8_rule84.md` with a summary containing these exact lines:

```
rule84_candidates: <n>
rule84_win_rate: <pct>
rule84_avg_R: <number>
```

plus a short plain-English paragraph — no code terms — explaining what the 84% rule is,
why it never showed up in the grading decks, and whether these candidates look worth
arming. Do **not** arm `RULE84` or change any trading gate; this row measures only.

The candidate list is also the input for the two-bar 84% grading deck Austin asked for —
say so at the top of the file and name `research/rule84_candidates.jsonl` as the deck's
source.

- **done-when:** `rule84_candidates.jsonl` has at least one candidate, `t8_rule84.md`
  carries all three metric lines and the plain-English paragraph, and no trading gate
  changed.
- **verify:**
  ```bash
  test -s research/rule84_candidates.jsonl
  python -c "
import json
rows=[json.loads(l) for l in open('research/rule84_candidates.jsonl')]
assert rows, 'no 84% candidates found'
need={'symbol','day','reclaim_bar'}
missing=[i for i,r in enumerate(rows) if not need <= set(r)]
assert not missing, f'rows missing required keys: {missing[:5]}'
print('OK', len(rows), 'rule84 candidates')
"
  grep -q "rule84_candidates:" research/t8_rule84.md
  grep -q "rule84_win_rate:" research/t8_rule84.md
  grep -q "rule84_avg_R:" research/t8_rule84.md
  python research/regression_gate.py
  ```

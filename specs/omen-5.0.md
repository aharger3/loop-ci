# OMEN 5.0 - Trade the way Austin trades

status: ready
version: omen-5.0
repo: aharger3/tradingbot
doc: Projects/OMEN.md

target: Fix the four mechanics that made the engine disagree with Austin on 78 of 80 graded cards — bar-close entries, wick-based stop-outs, no session window inside the detector, and a scattered mark corpus — then remeasure BR/OCR and the 84% rule separately.

## Why this version exists

Austin graded 80 fresh cards on 2026-08-11. Results:

| batch | n | S | A | C | X | S-precision |
|---|---|---|---|---|---|---|
| 84% rule | 40 | 2 | 4 | 0 | 34 | **5.0%** |
| OCR | 25 | 0 | 0 | 0 | 25 | **0.0%** |
| BR | 15 | 0 | 4 | 1 | 10 | **0.0%** |

Mining every note Austin has ever written (120 distinct noted marks across 8 files
plus 35 embedded in `specs/omen-4.0.md`) produced four repeated corrections. He has
now written each of them many times; none is in the code.

1. **"stop out happens when candle CLOSES below the level"** — written 5 times in
   this batch alone. `backtest_week.py:198` stops out on a wick touch
   (`c.low <= t.stop`). Every backtest loss therefore includes trades Austin would
   never have been stopped out of, and `research/rule84_candidates.jsonl` (2,843
   rows) is built entirely on phantom stop-outs. This is the single largest
   correctness defect in the engine.
2. **"the entry is N candles earlier"** — 31 notes, median 5 candles, 15 earlier
   vs 1 later. Plus **"enter as the candle is forming/closing"** 10 times. All 12
   signal sites in `signal_runner.py` hard-code `"entry": current.close`.
3. **"I dont trade past 11 am remember"** — `SignalRunner.detect_signals()` has no
   time gate at all. The 09:30–11:00 cutoff exists only in *callers*
   (`backtest_week.py:374`, `live_scanner.py:328`, `research/t4_engine_recall.py:184`),
   so any new caller silently loses it. That is exactly how 37 of the 80 homework
   cards were built outside the window and wasted.
4. **"dont want to be at low of day" / "not right at HOD"** — 21 notes.
   `BAR_EXTREME_FRAC=0.25` measures position inside the *signal candle*, not
   distance to the *session* extreme, and failing it only demotes S→A.

**Settled by Austin, 2026-08-11 — do not re-decide these:**

- Stop-out = **close beyond the level**. Wick touches do not stop anything out.
  Applies to BR, OCR and the 84% rule.
- Entry = **bar close by default**. Only when the close would land inside
  `BAR_EXTREME_FRAC` of the signal bar's extreme does the engine fill **intrabar at
  the level** instead ("those candles that move fast and close at high of day or
  low of day, i just want to try to not miss out").
- If the entry bar then **closes back beyond the level, scratch out at that close**.
  A scratch is not a loss and **does not arm the 84% rule**.
- 84% rule: **2 attempts total** (original + one re-entry). The **reclaim must also
  land before 11:00**.
- Session HOD/LOD proximity is a **veto**, not a demotion.
- **X stays one tag** and means "should not be traded". The alternative entries
  Austin names inside X notes become separate derived marks, not sub-codes.
- Universe is three pools. **Major 15**: NVDA TSLA AAPL SPCX MSFT MU INTC PLTR AMZN
  META AMD GOOGL ACHR NFLX ORCL. **MSTR is removed.** Indices/futures/ETFs track
  separately. The remaining omen-4 names stay live in a third pool with separate
  tracking.
- Backtest reports BR/OCR **separately** from the 84% rule.
- The 37 out-of-window cards are dropped, not regraded.

**Settled about the S rule itself, 2026-08-11:**

The S rule as written has **no positive quality clause**. S = clause 1 ("is it one of
three setups?") plus three *negative* filters. Nothing asks whether the setup is any
good — the detector's own A+/A/B/C quality score is deliberately never read
(`signal_runner.py:290-296`). BR fired 74,805 times across the archive; Austin takes 1–3
S a day. That inversion — S being the default for a detected setup rather than something
earned — is the reason S-precision is 0–5%, and no threshold tuning fixes it.

- **Pivot structure is a level type the engine has never had.** Austin trades off swing
  highs/lows and pivot structures, not only the six levels the engine knows (OR high/low,
  PDH/PDL, PMH/PML). His notes say it directly: "pivot structure break > level break",
  "dont see any levels, unless some were forgot to be marked", "no clean break it just
  respect pivot structures". **This is the biggest single gap and T10 builds it.**
- **S splits into two reported tiers, one grading scale.** The top **1–3 per day**
  universe-wide are `S+` — Austin's own words: "the top s trades which usually happen
  earlier in the day". The rest stay `S` and are **not discarded** — "i dont want that
  discarded, just put it in two separate tiers, not separate grading scale". Both are S
  for grading and corpus purposes; the split is a reporting rank, not a new tier letter.
- **Confluence is a bonus, not a requirement.** A bar where two of the three setups fire
  gets flagged and reported so we can measure whether his S marks cluster there. A lone
  clean setup can still be S.
- **"In-between mesh" is a hard S-veto.** His 2026-07-06 note — "middle of a bunch of
  levels, probability goes down significantly" — is in the rulebook as a C-condition and
  is implemented **nowhere in code**. It becomes a veto, not a demotion.
- **Displacement gets a written definition and is required for BR.** Cited in 18 of his
  notes as the S/A/C swing factor; appears in zero rule paragraphs. `BNR_DISPLACEMENT_GATE`
  has sat at `False` while the rulebook claims the break needs "volume/momentum".
- **Too much consolidation, or too long between break and retest, demotes BR and OCR** —
  Austin's own clause from 2026-08-10. Rules 7 and 10 are fully coded and dormant
  (`RULE_710_ENABLED = False`); they are exactly this rule.


### T1 -- Consolidate every mark Austin has ever written into austin_marks_v7.jsonl
- model: deepseek

Austin's marks are scattered and two thirds of his written notes are not in the live
corpus: `research/austin_marks_v6.jsonl` has 228 rows but only **40** carry a note,
while 120 distinct noted marks exist across `austin_marks_v2..v6.jsonl`,
`blind_marks_all.jsonl`, `marks_clean.jsonl`, `mark_batch_02_grades.jsonl`,
`mark_batch_03_regrades.jsonl`, `mark_batch_04_grades.jsonl`, and 35 more embedded as
raw JSON objects inside `specs/omen-4.0.md` in the loop-ci repo (not this one — those
35 are reproduced in `research/omen40_marks.jsonl` if present, otherwise skip them and
say so in the report).

Write `research/austin_marks_v7.jsonl`. One row per `(symbol, day, entry_i)`. Schema:
`id, symbol, day, entry_i, reclaim_i (84% only), austin_tier, setup, note, batch, source_files`.

Merge rules, in order:
- Deduplicate on `id`. When two sources disagree on `austin_tier`, the **newer batch
  wins** (batch05 > mark_batch_04 > mark_batch_03 > mark_batch_02 > v6 > v5 > ...).
- **Never drop a note.** If two sources have different notes for the same id,
  concatenate them with ` | `.
- Preserve `setup` when any source has one; `"none"` and `null` both mean no setup.

Then append these 80 new rows verbatim — Austin's 2026-08-11 grading batch:

```jsonl
 {"id":"MSTR_2026-01-27_35_48","symbol":"MSTR","day":"2026-01-27","batch":"batch05_84","entry_i":35,"austin_tier":"X","setup":"84","note":"","reclaim_i":48}
 {"id":"MSTR_2024-08-08_23_27","symbol":"MSTR","day":"2024-08-08","batch":"batch05_84","entry_i":23,"austin_tier":"A","setup":"84","note":"3 candles earlier is also an A entry, 84 percent rule same stop is ok","reclaim_i":27}
 {"id":"MSTR_2024-09-26_11_14","symbol":"MSTR","day":"2024-09-26","batch":"batch05_84","entry_i":11,"austin_tier":"X","setup":"84","note":"I dont see the stop out until later, stop out happens when candle CLOSES below the level ","reclaim_i":14}
 {"id":"MSTR_2024-04-24_33_52","symbol":"MSTR","day":"2024-04-24","batch":"batch05_84","entry_i":33,"austin_tier":"X","setup":"84","note":"candle PA ugly, would even trade this stock not apart of our top 14","reclaim_i":52}
 {"id":"MSTR_2026-04-22_79_87","symbol":"MSTR","day":"2026-04-22","batch":"batch05_84","entry_i":79,"austin_tier":"X","setup":"84","note":"","reclaim_i":87}
 {"id":"AAPL_2026-07-06_14_25","symbol":"AAPL","day":"2026-07-06","batch":"batch05_84","entry_i":14,"austin_tier":"X","setup":"84","note":"","reclaim_i":25}
 {"id":"AAPL_2024-03-28_7_61","symbol":"AAPL","day":"2024-03-28","batch":"batch05_84","entry_i":7,"austin_tier":"X","setup":"84","note":"4 candles after is an S entry OCR","reclaim_i":61}
 {"id":"AAPL_2025-01-13_18_28","symbol":"AAPL","day":"2025-01-13","batch":"batch05_84","entry_i":18,"austin_tier":"A","setup":"84","note":"3 candles earlier is an S entry, reclaim if you would've taken my s entry would've been two candles earlier, but yours is correct for the a trade","reclaim_i":28}
 {"id":"SPCX_2026-06-30_33_55","symbol":"SPCX","day":"2026-06-30","batch":"batch05_84","entry_i":33,"austin_tier":"X","setup":"84","note":"one candle earlier s entry, two candles earlier is the reclaim but could've taken off HOD earlier and stoped out on the rest and thats that. ill mark it x because your entry is wrong one candle late","reclaim_i":55}
 {"id":"MSTR_2026-05-21_70_77","symbol":"MSTR","day":"2026-05-21","batch":"batch05_84","entry_i":70,"austin_tier":"X","setup":"84","note":"","reclaim_i":77}
 {"id":"AAPL_2025-04-01_62_277","symbol":"AAPL","day":"2025-04-01","batch":"batch05_84","entry_i":62,"austin_tier":"X","setup":"84","note":"cans see what first two candles look like for the entry ","reclaim_i":277}
 {"id":"AAPL_2025-03-28_55_91","symbol":"AAPL","day":"2025-03-28","batch":"batch05_84","entry_i":55,"austin_tier":"X","setup":"84","note":"break and retest straddling the line","reclaim_i":91}
 {"id":"TSLA_2024-01-24_59_246","symbol":"TSLA","day":"2024-01-24","batch":"batch05_84","entry_i":59,"austin_tier":"X","setup":"84","note":"","reclaim_i":246}
 {"id":"PLTR_2026-05-06_15_18","symbol":"PLTR","day":"2026-05-06","batch":"batch05_84","entry_i":15,"austin_tier":"X","setup":"84","note":"","reclaim_i":18}
 {"id":"AMD_2024-10-22_26_87","symbol":"AMD","day":"2024-10-22","batch":"batch05_84","entry_i":26,"austin_tier":"X","setup":"84","note":"can't see what happens earlier","reclaim_i":87}
 {"id":"MSTR_2025-12-05_17_102","symbol":"MSTR","day":"2025-12-05","batch":"batch05_84","entry_i":17,"austin_tier":"X","setup":"84","note":"can't see what happens earlier","reclaim_i":102}
 {"id":"MSTR_2024-03-20_73_78","symbol":"MSTR","day":"2024-03-20","batch":"batch05_84","entry_i":73,"austin_tier":"X","setup":"84","note":"stop outs only happen when candle closes by the way","reclaim_i":78}
 {"id":"TSLA_2026-02-12_38_71","symbol":"TSLA","day":"2026-02-12","batch":"batch05_84","entry_i":38,"austin_tier":"X","setup":"84","note":"","reclaim_i":71}
 {"id":"INTC_2025-02-27_72_153","symbol":"INTC","day":"2025-02-27","batch":"batch05_84","entry_i":72,"austin_tier":"X","setup":"84","note":"I see an entry 14 candles later an S entry, your I would need to see what happened earlier, and I dont trade past 11 am remember","reclaim_i":153}
 {"id":"MU_2026-07-24_16_20","symbol":"MU","day":"2026-07-24","batch":"batch05_84","entry_i":16,"austin_tier":"A","setup":"84","note":"another a entry 6 candles earlier, I dont see a stop out because you would've held a OCR green candle wick","reclaim_i":20}
 {"id":"NVDA_2025-05-21_18_80","symbol":"NVDA","day":"2025-05-21","batch":"batch05_84","entry_i":18,"austin_tier":"X","setup":"84","note":"dont know what earlier candles look like","reclaim_i":80}
 {"id":"MSFT_2025-04-17_16_36","symbol":"MSFT","day":"2025-04-17","batch":"batch05_84","entry_i":16,"austin_tier":"X","setup":"84","note":"3 candles earlier is an S our entry, wouldn't need 84 percent becasse you would have gotten LOD, but your trade was wrong","reclaim_i":36}
 {"id":"MU_2026-02-09_24_36","symbol":"MU","day":"2026-02-09","batch":"batch05_84","entry_i":24,"austin_tier":"S","setup":"84","note":"first well understanding ive seen, however stop out would've been 5 candles later because thats when the close below happened","reclaim_i":36}
 {"id":"MU_2026-03-24_40_41","symbol":"MU","day":"2026-03-24","batch":"batch05_84","entry_i":40,"austin_tier":"X","setup":"84","note":"","reclaim_i":41}
 {"id":"TSLA_2025-06-12_56_61","symbol":"TSLA","day":"2025-06-12","batch":"batch05_84","entry_i":56,"austin_tier":"X","setup":"84","note":"","reclaim_i":61}
 {"id":"MSFT_2026-04-17_21_60","symbol":"MSFT","day":"2026-04-17","batch":"batch05_84","entry_i":21,"austin_tier":"X","setup":"84","note":"","reclaim_i":60}
 {"id":"PLTR_2025-12-10_45_52","symbol":"PLTR","day":"2025-12-10","batch":"batch05_84","entry_i":45,"austin_tier":"X","setup":"84","note":"perfect S entry orc BR confluence, however because the candle didn't close BELOW the stop, there is no 84 percent rule, you would've taken off at HOD and stopped out BE","reclaim_i":52}
 {"id":"MU_2025-07-17_6_8","symbol":"MU","day":"2025-07-17","batch":"batch05_84","entry_i":6,"austin_tier":"X","setup":"84","note":"your trades was wrong. S BR entry, LOD hit so no need for 84 percent rule here","reclaim_i":8}
 {"id":"INTC_2024-11-22_18_137","symbol":"INTC","day":"2024-11-22","batch":"batch05_84","entry_i":18,"austin_tier":"X","setup":"84","note":"can't see what happens before","reclaim_i":137}
 {"id":"NVDA_2026-02-05_48_52","symbol":"NVDA","day":"2026-02-05","batch":"batch05_84","entry_i":48,"austin_tier":"X","setup":"84","note":"1 candle earlier is your  A entry, stop out doesn't happen until 10:37, so dont see an 84 percent rule occur","reclaim_i":52}
 {"id":"NVDA_2025-09-29_13_23","symbol":"NVDA","day":"2025-09-29","batch":"batch05_84","entry_i":13,"austin_tier":"X","setup":"84","note":"1 candle earlier is S entry, no stop out occurs ","reclaim_i":23}
 {"id":"AAPL_2025-10-01_26_48","symbol":"AAPL","day":"2025-10-01","batch":"batch05_84","entry_i":26,"austin_tier":"X","setup":"84","note":"","reclaim_i":48}
 {"id":"AAPL_2025-06-11_20_37","symbol":"AAPL","day":"2025-06-11","batch":"batch05_84","entry_i":20,"austin_tier":"X","setup":"84","note":"","reclaim_i":37}
 {"id":"MSFT_2024-01-25_52_70","symbol":"MSFT","day":"2024-01-25","batch":"batch05_84","entry_i":52,"austin_tier":"X","setup":"84","note":"your entry never closed below the stop so no need 84 percent rule, but get a better fill not at HOD","reclaim_i":70}
 {"id":"META_2025-09-18_45_58","symbol":"META","day":"2025-09-18","batch":"batch05_84","entry_i":45,"austin_tier":"X","setup":"84","note":"1 candle earlier A entry, 6 candles earlier then that is an A entry too","reclaim_i":58}
 {"id":"AMD_2025-10-14_75_137","symbol":"AMD","day":"2025-10-14","batch":"batch05_84","entry_i":75,"austin_tier":"X","setup":"84","note":"dont know what happened before and its late in the day","reclaim_i":137}
 {"id":"AMD_2024-11-11_22_29","symbol":"AMD","day":"2024-11-11","batch":"batch05_84","entry_i":22,"austin_tier":"A","setup":"84","note":"s entry 4 candles earlier, still decent entry and reclaim would've been the same","reclaim_i":29}
 {"id":"AMD_2025-08-27_7_64","symbol":"AMD","day":"2025-08-27","batch":"batch05_84","entry_i":7,"austin_tier":"X","setup":"84","note":"dont know what happens earlier","reclaim_i":64}
 {"id":"MSTR_2026-04-02_77_91","symbol":"MSTR","day":"2026-04-02","batch":"batch05_84","entry_i":77,"austin_tier":"X","setup":"84","note":"","reclaim_i":91}
 {"id":"NVDA_2025-11-28_14_22","symbol":"NVDA","day":"2025-11-28","batch":"batch05_84","entry_i":14,"austin_tier":"S","setup":"84","note":"I would raise the stop after the second time to the higher piece of the pivot structure","reclaim_i":22}
 {"id":"AAPL_2025-03-12_329","symbol":"AAPL","day":"2025-03-12","batch":"batch05_OCR","entry_i":329,"austin_tier":"X","setup":"none","note":""}
 {"id":"AAPL_2025-03-24_244","symbol":"AAPL","day":"2025-03-24","batch":"batch05_OCR","entry_i":244,"austin_tier":"X","setup":"none","note":""}
 {"id":"AAPL_2025-06-12_162","symbol":"AAPL","day":"2025-06-12","batch":"batch05_OCR","entry_i":162,"austin_tier":"X","setup":"none","note":""}
 {"id":"AAPL_2025-09-09_123","symbol":"AAPL","day":"2025-09-09","batch":"batch05_OCR","entry_i":123,"austin_tier":"X","setup":"none","note":""}
 {"id":"AAPL_2025-12-22_290","symbol":"AAPL","day":"2025-12-22","batch":"batch05_OCR","entry_i":290,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"AMD_2025-03-28_31","symbol":"AMD","day":"2025-03-28","batch":"batch05_OCR","entry_i":31,"austin_tier":"X","setup":"none","note":"earlier entry at 9:39 as candle forming not at HOD was s trade, yours a fail"}
 {"id":"AMZN_2025-12-09_370","symbol":"AMZN","day":"2025-12-09","batch":"batch05_OCR","entry_i":370,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"GOOGL_2026-01-20_67","symbol":"GOOGL","day":"2026-01-20","batch":"batch05_OCR","entry_i":67,"austin_tier":"X","setup":"none","note":"I see way to Many break and retests with no displacement and red candles respected earlier, way too late"}
 {"id":"INTC_2024-01-23_219","symbol":"INTC","day":"2024-01-23","batch":"batch05_OCR","entry_i":219,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"META_2025-03-05_335","symbol":"META","day":"2025-03-05","batch":"batch05_OCR","entry_i":335,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"MSFT_2024-06-07_327","symbol":"MSFT","day":"2024-06-07","batch":"batch05_OCR","entry_i":327,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"MSTR_2024-10-16_188","symbol":"MSTR","day":"2024-10-16","batch":"batch05_OCR","entry_i":188,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"MSTR_2024-12-17_89","symbol":"MSTR","day":"2024-12-17","batch":"batch05_OCR","entry_i":89,"austin_tier":"X","setup":"none","note":"chop"}
 {"id":"MSTR_2026-01-13_307","symbol":"MSTR","day":"2026-01-13","batch":"batch05_OCR","entry_i":307,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"MSTR_2026-04-02_285","symbol":"MSTR","day":"2026-04-02","batch":"batch05_OCR","entry_i":285,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"MSTR_2026-06-12_362","symbol":"MSTR","day":"2026-06-12","batch":"batch05_OCR","entry_i":362,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"MU_2024-01-05_151","symbol":"MU","day":"2024-01-05","batch":"batch05_OCR","entry_i":151,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"NVDA_2024-10-31_276","symbol":"NVDA","day":"2024-10-31","batch":"batch05_OCR","entry_i":276,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"PLTR_2025-06-04_311","symbol":"PLTR","day":"2025-06-04","batch":"batch05_OCR","entry_i":311,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"SPCX_2026-06-15_226","symbol":"SPCX","day":"2026-06-15","batch":"batch05_OCR","entry_i":226,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"SPCX_2026-06-24_271","symbol":"SPCX","day":"2026-06-24","batch":"batch05_OCR","entry_i":271,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"SPCX_2026-07-01_306","symbol":"SPCX","day":"2026-07-01","batch":"batch05_OCR","entry_i":306,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"SPCX_2026-07-13_272","symbol":"SPCX","day":"2026-07-13","batch":"batch05_OCR","entry_i":272,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"SPCX_2026-08-04_107","symbol":"SPCX","day":"2026-08-04","batch":"batch05_OCR","entry_i":107,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"TSLA_2025-05-22_379","symbol":"TSLA","day":"2025-05-22","batch":"batch05_OCR","entry_i":379,"austin_tier":"X","setup":"OCR","note":""}
 {"id":"AAPL_2024-01-02_19","symbol":"AAPL","day":"2024-01-02","batch":"batch05_BR","entry_i":19,"austin_tier":"A","setup":"BR","note":"1 candle earlier is your entry"}
 {"id":"AAPL_2024-10-28_162","symbol":"AAPL","day":"2024-10-28","batch":"batch05_BR","entry_i":162,"austin_tier":"X","setup":"none","note":"tight and chop in-between channels"}
 {"id":"AAPL_2025-09-09_279","symbol":"AAPL","day":"2025-09-09","batch":"batch05_BR","entry_i":279,"austin_tier":"C","setup":"none","note":"never retested any kind of level or green candle with displacement, but below all the levels and with a good thesis I can see it but its risky"}
 {"id":"MSTR_2024-01-02_244","symbol":"MSTR","day":"2024-01-02","batch":"batch05_BR","entry_i":244,"austin_tier":"X","setup":"none","note":""}
 {"id":"MSTR_2024-08-14_66","symbol":"MSTR","day":"2024-08-14","batch":"batch05_BR","entry_i":66,"austin_tier":"X","setup":"none","note":""}
 {"id":"MSTR_2025-04-14_183","symbol":"MSTR","day":"2025-04-14","batch":"batch05_BR","entry_i":183,"austin_tier":"X","setup":"BR","note":"analyzing if this was from 9:30-11: displacement on entry but a couple candles exist from earlier in the day but they are volitale and lengthy so its not as big of a issue"}
 {"id":"MSTR_2025-12-12_11","symbol":"MSTR","day":"2025-12-12","batch":"batch05_BR","entry_i":11,"austin_tier":"A","setup":"BR","note":"5 candles earlier is your s entry"}
 {"id":"MU_2024-01-02_26","symbol":"MU","day":"2024-01-02","batch":"batch05_BR","entry_i":26,"austin_tier":"X","setup":"none","note":""}
 {"id":"NVDA_2024-01-03_98","symbol":"NVDA","day":"2024-01-03","batch":"batch05_BR","entry_i":98,"austin_tier":"A","setup":"OCR","note":"outside timeframe I trade but if it was its an A because there were nearly earlier entries"}
 {"id":"PLTR_2024-01-02_196","symbol":"PLTR","day":"2024-01-02","batch":"batch05_BR","entry_i":196,"austin_tier":"X","setup":"none","note":"wrong timeframe"}
 {"id":"SPCX_2024-01-30_7","symbol":"SPCX","day":"2024-01-30","batch":"batch05_BR","entry_i":7,"austin_tier":"A","setup":"BR","note":"hard to tell how great the candles look for the b and r"}
 {"id":"SPCX_2026-06-29_47","symbol":"SPCX","day":"2026-06-29","batch":"batch05_BR","entry_i":47,"austin_tier":"X","setup":"none","note":"overextended and no great entry presented itself"}
 {"id":"SPCX_2026-07-15_55","symbol":"SPCX","day":"2026-07-15","batch":"batch05_BR","entry_i":55,"austin_tier":"X","setup":"none","note":""}
 {"id":"SPCX_2026-07-30_215","symbol":"SPCX","day":"2026-07-30","batch":"batch05_BR","entry_i":215,"austin_tier":"X","setup":"none","note":""}
 {"id":"TSLA_2024-01-03_16","symbol":"TSLA","day":"2024-01-03","batch":"batch05_BR","entry_i":16,"austin_tier":"X","setup":"none","note":"2 or 3 candles later is a S BR for puts"}
```

Also write `research/t1_corpus_v7.md` with a table of: source file, rows read, rows
new, rows whose tier was overwritten, notes preserved. Include the line
`noted_marks: <count>` where count = rows in v7 with a non-empty `note`.

- **done-when:** `research/austin_marks_v7.jsonl` exists, holds at least 300 unique
  ids, at least 140 of them carry a non-empty note, and all 80 batch05 ids above are
  present with the exact tiers given.
- **verify:**
  ```bash
  python -c "
  import json
  rows=[json.loads(l) for l in open('research/austin_marks_v7.jsonl') if l.strip()]
  ids={r['id'] for r in rows}
  assert len(ids)==len(rows), 'duplicate ids in v7'
  assert len(rows)>=300, f'only {len(rows)} rows'
  noted=[r for r in rows if (r.get('note') or '').strip()]
  assert len(noted)>=140, f'only {len(noted)} noted rows'
  b5=[r for r in rows if str(r.get('batch','')).startswith('batch05')]
  assert len(b5)==80, f'batch05 rows: {len(b5)}'
  import collections; c=collections.Counter(r['austin_tier'] for r in b5)
  assert c['S']==2 and c['A']==8 and c['C']==1 and c['X']==69, dict(c)
  print('v7 OK', len(rows), 'rows,', len(noted), 'noted')
  "
  test -s research/t1_corpus_v7.md
  ```


### T2 -- Extract the alternative entries Austin names inside his notes
- model: glm
- depends-on: T1

Austin's X notes routinely name the trade he *would* have taken: "1 candle earlier is
S entry", "3 candles earlier is an S entry", "4 candles after is an S entry OCR",
"5 candles earlier is your s entry". These are free S/A labels the corpus has never
read. A scan of batch05 alone finds 14 (7 of them S); omen-4.0's notes hold roughly 13
more.

Read every row of `research/austin_marks_v7.jsonl` with a non-empty note. For each note,
extract every phrase of the form `<N> candle(s|bars) <earlier|before|later|after>` that
is associated with a tier letter (S/A/C) within the same clause. Word-numbers count
("one", "two", ... "ten"). Emit one row per extraction to
`research/derived_marks_v2.jsonl`:

`{"id": "<SYM>_<day>_<derived_i>", "symbol", "day", "entry_i": <derived_i>, "austin_tier": "<S|A|C>", "setup": "<from the note if named, else inherit parent>", "derived_from": "<parent id>", "offset": <signed int, positive = earlier>, "note": "<the source phrase>", "batch": "derived_v2"}`

`derived_i = parent.entry_i - offset` for "earlier"/"before", `parent.entry_i + N` for
"later"/"after". Drop any row where `derived_i < 0` or `derived_i > 90` (the 09:30–11:00
window is 90 one-minute bars). Drop any row whose `derived_i` collides with an id already
in v7 — the explicit grade wins.

Then append the surviving rows to `research/austin_marks_v7.jsonl` and write
`research/t2_derived.md` listing every extraction with its parent, including the line
`derived_added: <count>`.

- **done-when:** `research/derived_marks_v2.jsonl` holds at least 15 rows, at least 6
  of them tier S, every row's `derived_i` is inside 0–90, and each one is appended to v7.
- **verify:**
  ```bash
  python -c "
  import json
  d=[json.loads(l) for l in open('research/derived_marks_v2.jsonl') if l.strip()]
  assert len(d)>=15, f'only {len(d)} derived'
  assert sum(1 for r in d if r['austin_tier']=='S')>=6, 'too few derived S'
  assert all(0<=r['entry_i']<=90 for r in d), 'derived bar outside 09:30-11:00'
  assert all(r.get('derived_from') for r in d), 'missing parent link'
  v7={json.loads(l)['id'] for l in open('research/austin_marks_v7.jsonl') if l.strip()}
  missing=[r['id'] for r in d if r['id'] not in v7]
  assert not missing, f'not merged into v7: {missing[:5]}'
  print('derived OK', len(d))
  "
  grep -q '^derived_added: [0-9]' research/t2_derived.md
  ```


### T3 -- signal_runner.py: session window, intrabar fill, HOD/LOD veto, 84% caps
- model: opus

Four mechanics, all in `signal_runner.py`. Each gets a module-level constant in the
same style as the existing `BNR_DISPLACEMENT_GATE` / `S_GATE` block, env-overridable,
and the new behaviour is the **default on** (this version exists to change behaviour,
not to add another dormant flag).

**(a) Session window inside the detector.** Today `SignalRunner.detect_signals()`
(line ~918) has no time gate; the 09:30–11:00 cutoff lives only in callers
(`backtest_week.py:374`, `live_scanner.py:328`, `research/t4_engine_recall.py:184`), so
any new caller silently loses it — that is how 37 of 80 homework cards got built
outside the window. Add:

```python
SESSION_START = os.getenv("SESSION_START", "09:30:00")
SESSION_END   = os.getenv("SESSION_END", "11:00:00")   # Austin: "I dont trade past 11 am"
```

and return `[]` from `detect_signals()` when the current candle's timestamp is outside
`[SESSION_START, SESSION_END)`. Leave the caller-side cutoffs in place; they become
redundant, not wrong.

**(b) Intrabar fill on an extreme close.** All 12 signal sites hard-code
`"entry": current.close`. Austin enters at the close *most of the time*, but when a
fast candle closes at the session extreme he enters intrabar at the level instead —
"those candles that move fast and close at high of day or low of day, i just want to
try to not miss out". Add one helper and call it at every one of those 12 sites:

```python
def fill_price(level: float, candle, is_long: bool) -> float:
    """Austin 2026-08-11: fill at the close, except when the close sits inside
    BAR_EXTREME_FRAC of the bar's own extreme in the trade direction — then fill at
    the level, which is where he actually enters as the candle is forming."""
```

Return `candle.close` unless `bar_extreme_veto` would fire for this bar and direction,
in which case return `level` clamped into `[candle.low, candle.high]`. `level` is the
pivot / order-block / break level the signal is keyed to — each site already has it in
scope for its `reason` string.

**(c) Session HOD/LOD proximity veto.** 21 of Austin's notes say some form of "dont
want to be at low of day" / "not right at HOD". The existing `BAR_EXTREME_FRAC=0.25`
measures position inside the *signal candle*, and failing it only demotes S→A. Add a
separate, harder check against the *session so far*:

```python
SESSION_EXTREME_FRAC = float(os.getenv("SESSION_EXTREME_FRAC", "0.10"))
```

Veto the signal outright (do not emit it) when a long's fill sits within
`SESSION_EXTREME_FRAC * (session_high - session_low)` of the session high so far, or a
short's fill within that distance of the session low so far. "Session so far" = candles
from `SESSION_START` up to and including the signal bar. Do not use future bars.

Then A/B it: run the detector over the equity pool at
`SESSION_EXTREME_FRAC` in `{0.00, 0.05, 0.10, 0.20}` and write
`research/t3_session_extreme.md` with a row per setting giving fires, and S-precision
measured against `research/austin_marks_v7.jsonl`. Include the line
`chosen_frac: <value>` naming the setting with the highest S-precision that still emits
at least 40% of the fires the 0.00 setting emits, and set the default constant to it.

**(d) 84% rule caps.** Austin settled two limits: at most **2 attempts on one idea**
(the original plus a single re-entry — "2 is usual"), and the **reclaim must also land
before 11:00**. Enforce both where `SignalType.REENTRY_84_RULE` is emitted (lines ~1162
and ~1346): refuse to emit a re-entry when the idea already has two attempts today, or
when the reclaim bar's timestamp is at or past `SESSION_END`.

**(e) Fix the stale test suite.** `test_austin_tier.py` is **already broken on main**:
line 163 raises `IndexError: list index out of range` because the test still expects a
repeat idea to emit an additive row, while omen-4.0 shipped `NO_REPEAT_ENTRIES = True`
which suppresses the second signal entirely. Nothing has run this file since. Update the
"the same idea still ROUTES the second time" case to assert the current, settled
behaviour (no second row when `NO_REPEAT_ENTRIES` is on; the 84% re-entry stays the one
exemption), then extend the suite with a case for each of (a)–(d) above.

- **done-when:** all four constants exist and are honoured, `test_austin_tier.py` runs
  green end-to-end with no FAIL line and no traceback,
  `research/t3_session_extreme.md` names a chosen fraction, and a signal on a bar
  timestamped 11:30 is not emitted.
- **verify:**
  ```bash
  python -m py_compile signal_runner.py
  python test_austin_tier.py 2>&1 | tee /tmp/t3_tests.txt
  test $? -eq 0
  ! grep -q 'FAIL\|Traceback' /tmp/t3_tests.txt
  python -c "
  import signal_runner as sr, inspect
  missing=[n for n in ('SESSION_START','SESSION_END','SESSION_EXTREME_FRAC') if not hasattr(sr,n)]
  assert not missing, 'missing constants: %s' % missing
  assert sr.SESSION_END=='11:00:00', sr.SESSION_END
  assert callable(getattr(sr,'fill_price',None)), 'fill_price helper missing'
  src=inspect.getsource(sr.SignalRunner.detect_signals)
  assert 'SESSION_END' in src, 'detect_signals has no session gate'
  body=open('signal_runner.py').read()
  assert body.count('\"entry\": current.close') == 0, 'some sites still fill at close unconditionally'
  assert 'fill_price(' in body, 'fill_price never called'
  print('signal_runner OK, chosen SESSION_EXTREME_FRAC =', sr.SESSION_EXTREME_FRAC)
  "
  grep -q '^chosen_frac: [0-9.]*$' research/t3_session_extreme.md
  ```


### T4 -- backtest_week.py: stop out on the CLOSE, and scratch a failed entry bar
- model: opus

This is the largest correctness defect in the engine. `backtest_week.py:198` reads

```python
if (c.low <= t.stop) if long else (c.high >= t.stop):
```

— a **wick touch** stops the trade out. Austin has written the correction five times in
one batch: *"stop out happens when candle CLOSES below the level"*, *"stop outs only
happen when candle closes by the way"*, *"your entry never closed below the stop so no
need 84 percent rule"*, *"because the candle didn't close BELOW the stop, there is no 84
percent rule"*, *"stop out doesn't happen until 10:37"*. Every backtest loss to date
includes trades he would still have been holding, and `research/rule84_candidates.jsonl`
(2,843 rows) is a pool of phantom stop-outs — which is why 34 of his 40 rule84 cards
came back X.

**(a)** Change every stop-hit test in `_ladder_bar` (and any other stop test in the
file, including the runner/breakeven stop at line ~209) from wick to close:
`c.close <= t.stop` for longs, `c.close >= t.stop` for shorts. Exit price stays
`t.stop` — Austin's stop order still fills at the level; only the *trigger* moves to
the close. Add a module constant `STOP_ON_CLOSE = os.getenv("STOP_ON_CLOSE","1") not in
("0","false")` so the old behaviour is reproducible for the A/B below, default **on**.

**(b)** Scratch a failed entry bar. Per Austin, an entry taken intrabar that then closes
back beyond the level is not a loss — "scratch out at close, no 84 percent, this rule
and previous applys to BR and OCR as well". On the bar the trade is entered, if the
close is on the wrong side of the entry level, exit at that close with
`outcome = "scratch"`, and **do not** call `_arm_84`.

**(c)** `_arm_84` fires only on a close-based full stop-out. It already requires
`t.counted` and an unscaled trade; add that `t.outcome == "loss"` (not `"scratch"`) and
that the stop-out bar's timestamp is before 11:00. Keep the existing
`RULE84_ARM_ON` / `RULE84_STRICT` gates untouched.

Then A/B the change: run the same 12-month backtest with `STOP_ON_CLOSE=0` and
`STOP_ON_CLOSE=1` over the major pool and write `research/t4_stop_on_close.md` with
these exact lines plus a per-setup table:

```
win_rate_wick: <pct>
win_rate_close: <pct>
trades_wick: <n>
trades_close: <n>
scratches_close: <n>
arm84_wick: <n>
arm84_close: <n>
```

- **done-when:** no stop test in the file uses `.low`/`.high` against a stop level,
  scratches exist as a distinct outcome, `_arm_84` never fires on a scratch, and the
  A/B report is written with all seven lines above.
- **verify:**
  ```bash
  python -m py_compile backtest_week.py
  python -c "
  import re
  s=open('backtest_week.py').read()
  bad=re.findall(r'c\.(?:low|high)\s*[<>]=\s*(?:t\.stop|stop_lv|t\.runner_stop)', s)
  assert not bad, f'wick-based stop tests remain: {bad}'
  assert re.search(r'c\.close\s*<=\s*t\.stop', s), 'no close-based long stop'
  assert 'scratch' in s, 'no scratch outcome'
  assert 'STOP_ON_CLOSE' in s, 'missing STOP_ON_CLOSE flag'
  print('stop semantics OK')
  "
  python -c "
  import re
  r=open('research/t4_stop_on_close.md').read()
  need=['win_rate_wick:','win_rate_close:','trades_wick:','trades_close:','scratches_close:','arm84_wick:','arm84_close:']
  miss=[k for k in need if not re.search('^'+re.escape(k)+r'\s*\S', r, re.M)]
  assert not miss, f'missing lines: {miss}'
  print('A/B report OK')
  "
  ```


### T5 -- Three tracked pools, MSTR out, ACHR/NFLX/ORCL in
- model: deepseek

The symbol lists disagree with each other and with Austin. `_t3_stage.py:20` has a
13-name `EQUITY_POOL`; `live_scanner.py:50` trades a different 27-name
`DEFAULT_SYMBOLS`; `archive_1m.py:21` and `build_corpus_instances.py:27` each have
their own. Austin settled the split on 2026-08-11 — three pools, tracked separately:

Create `universe.py` as the single source of truth:

```python
MAJOR_15 = ["NVDA","TSLA","AAPL","SPCX","MSFT","MU","INTC","PLTR",
            "AMZN","META","AMD","GOOGL","ACHR","NFLX","ORCL"]
INDEX_POOL = ["QQQ","SPY","IWM"]      # + futures/ETFs tradeable on prop firms
OTHER_POOL = [...]                    # everything else currently in live_scanner
                                      # DEFAULT_SYMBOLS minus MAJOR_15/INDEX_POOL
POOL_OF = {sym: name for ...}         # reverse lookup, used for per-pool reporting
```

**MSTR is removed from every pool** — Austin: "would even trade this stock not apart of
our top 14". ACHR, NFLX and ORCL join MAJOR_15. Then make `_t3_stage.py`,
`archive_1m.py`, `build_corpus_instances.py` and `live_scanner.py` import from
`universe.py` instead of holding their own literal lists. `live_scanner.py` keeps
scanning all three pools, but every signal it emits must carry a `pool` field so the
three track separately.

Note in `research/t5_universe.md` that `data_archive/` currently has **0 days for
ACHR**, 507 for NFLX, 274 for ORCL — ACHR cannot be backtested until T6 lands.

- **done-when:** `universe.py` exists, MAJOR_15 is exactly the 15 names above, MSTR is
  in none of the three pools, and the four consumer modules import it rather than
  redefining a list.
- **verify:**
  ```bash
  python -c "
  import universe as u
  want=['NVDA','TSLA','AAPL','SPCX','MSFT','MU','INTC','PLTR','AMZN','META','AMD','GOOGL','ACHR','NFLX','ORCL']
  assert u.MAJOR_15==want, u.MAJOR_15
  allsyms=set(u.MAJOR_15)|set(u.INDEX_POOL)|set(u.OTHER_POOL)
  assert 'MSTR' not in allsyms, 'MSTR still in a pool'
  assert not (set(u.MAJOR_15)&set(u.OTHER_POOL)), 'pools overlap'
  assert all(u.POOL_OF[s]=='MAJOR_15' for s in u.MAJOR_15)
  print('universe OK', len(allsyms), 'symbols')
  "
  python -c "
  F=('_t3_stage.py','archive_1m.py','build_corpus_instances.py','live_scanner.py')
  src={f:open(f).read() for f in F}
  noimp=[f for f in F if 'universe' not in src[f]]
  assert not noimp, 'does not import universe: %s' % noimp
  still=[f for f in F if 'MSTR' in src[f]]
  assert not still, 'still names MSTR: %s' % still
  print('consumers rewired')
  "
  test -s research/t5_universe.md
  ```


### T6 -- Archive 1-minute data for ACHR and top up ORCL
- model: deepseek

`data_archive/` has 0 days for ACHR and only 274 for ORCL, against 507+ for the rest of
the pool. Both are new members of MAJOR_15 and cannot be backtested or graded without
bars. Run `archive_1m.py` for ACHR and ORCL over the same date span the existing pool
covers (take the min/max day present under `data_archive/NVDA/` as the target span).

If `POLYGON_API_KEY` is absent from the runner environment, fail loudly rather than
writing partial files — a half-archived symbol produces silently wrong backtests.

Write `research/t6_archive.md` with a per-symbol line
`<SYM>: <days_before> -> <days_after>`.

- **done-when:** `data_archive/ACHR/` holds at least 400 day files and `data_archive/ORCL/`
  at least 450, and the report names both.
- **verify:**
  ```bash
  test $(ls data_archive/ACHR 2>/dev/null | wc -l) -ge 400
  test $(ls data_archive/ORCL 2>/dev/null | wc -l) -ge 450
  grep -q '^ACHR: ' research/t6_archive.md
  grep -q '^ORCL: ' research/t6_archive.md
  ```


### T7 -- Write the corrected rules into Trading-Bot-Rulesets.md
- model: glm

Austin repeats these in his notes because they are not written down anywhere. Add each
as its own numbered clause in `Trading-Bot-Rulesets.md`, in his words, with the mark ids
that establish it. Do not paraphrase away the specifics.

1. **Stop-outs happen on the close, not the wick.** A trade is stopped out only when a
   candle *closes* beyond the stop level. Evidence: `MSTR_2024-09-26_11_14`,
   `MSTR_2024-03-20_73_78`, `MU_2026-02-09_24_36`, `PLTR_2025-12-10_45_52`,
   `MSFT_2024-01-25_52_70`, `NVDA_2026-02-05_48_52`.
2. **Entry is the close, except on an extreme close.** Normally enter on the candle
   close. When a fast candle would close at the session high (long) or low (short),
   enter intrabar at the level instead — "you want it to look like it will close above
   that". If the bar then closes back beyond the level, scratch out at that close; a
   scratch is not a loss and does not arm the 84% rule. Evidence: the 10 "enter as the
   candle is forming/closing" notes, `AMD_2025-03-28_31`.
3. **Nothing is traded outside 09:30–11:00**, and that includes the 84% reclaim leg —
   a re-entry is an entry. Evidence: `INTC_2025-02-27_72_153`, `PLTR_2024-01-02_196`,
   `NVDA_2024-01-03_98`, `AMD_2025-10-14_75_137`.
4. **Do not enter at the session extreme.** Distinct from the existing
   `BAR_EXTREME_FRAC` clause, which measures position inside the signal candle. This one
   measures distance to the day's high/low so far and is a veto, not a demotion.
   Evidence: 21 HOD/LOD notes including `MSFT_2024-01-25_52_70`
   ("get a better fill not at HOD"), `AMD_2025-03-28_31`.

Also add a short **"the 84% rule takes 2 attempts, not 3"** line under the existing 84%
section, citing `CRM_2024-11-11_14`.

Then rewrite the **"Austin's Tiers (S / A / C / X)"** section, because the S rule as
written is the root problem. Today S = clause 1 plus three *negative* filters and nothing
positive; add these as clauses in his words, with evidence ids:

5. **Displacement.** Define it once, concretely, and require it for break-and-retest:
   the break leg must show displacement — a decisive move off the level rather than a
   drift — and a B&R without it can never be S. Give the definition in bars and range
   terms so `BNR_DISPLACEMENT_GATE` implements exactly what the paragraph says, not an
   interpretation of it. Evidence: `GOOGL_2026-01-20_67` ("way to Many break and retests
   with no displacement"), `QQQ_2024-05-08_8`, `SPY_2024-07-11_44`, `TSLA_2024-12-03_17`,
   `NVDA_2024-11-18_10`.
6. **Too much consolidation, or too slow a retest, demotes.** Austin, 2026-08-10: OCR and
   BR with too much consolidation, or too long between the break and the retest of the
   level or one candle, are subject to demotion. Rules 7 (retest speed) and 10 (left-side
   pivot count) already state this numerically — cite them here so the paragraph and the
   code are the same rule. Evidence: `MSFT_2025-03-20_28` ("too much consolidation before
   entry"), `NVDA_2024-11-13_17` ("too choppy and taking too long"), `QQQ_2024-07-24_23`,
   `MSTR_2024-12-17_89` ("chop").
7. **In-between mesh is a hard veto, not a demotion.** Austin, 2026-07-06: "middle of a
   bunch of levels, probability goes down significantly." Currently written in this
   document as a C-condition and implemented nowhere. Evidence: `AAPL_2024-10-28_162`
   ("tight and chop in-between channels"), `SPCX_2026-06-29_47` ("overextended and no
   great entry presented itself").
8. **Pivot structure is a level.** Swing highs and lows are levels Austin trades off, on
   equal footing with OR high/low, PDH/PDL and PMH/PML, and a break of pivot structure
   outranks a break of a named level. Evidence: `AMZN_2025-07-17_34` ("pivot-structure
   break > level break"), `NVDA_2024-09-06_53` ("no clean break it just respect pivot
   structures"), `TSLA_2024-12-03_17` ("break/retest of a 2-candle structure, not a large
   pivot"), `NVDA_2025-11-28_14_22` ("raise the stop to the higher piece of the pivot
   structure").
9. **S+ and S.** All S signals stay S on one grading scale. The top **1–3 per day**
   universe-wide are reported as `S+` — "the top s trades which usually happen earlier in
   the day". The rest are still S and are **never discarded**. This is a reporting rank,
   not a fifth tier letter.
10. **Confluence is a bonus.** Two of the three setups firing on the same bar is recorded
    and reported, never required. Evidence: `PLTR_2025-12-10_45_52` ("perfect S entry orc
    BR confluence"), `NVDA_2024-12-16_14` ("OCR+BR confluence").

11. **The remaining clauses pulled from his notes.** Write each as its own short line so
    a later version can implement it: **wick-touch is a hard filter for break-and-retest
    too**, not only for the one candle rule (`PLTR_2024-10-23_10`, "wick not touching a
    level"); a **pre-signal wick raises confidence** (`IWM_2024-04-03_13`, "large wick
    before candle entry gives confidence even though it's not the absolute strongest green
    candle"); a **trendline break wants a second confirmation candle with strength**
    (`ORCL_2025-03-28_12`). Mark these three explicitly as **written but not yet
    implemented** so nobody mistakes the paragraph for shipped behaviour.

Finally, add a **reclaim-speed** line under the 84% section: a reclaim that takes a long
time is not the same trade as a fast one and demotes — Austin graded `AMD_2026-05-14_67`
an A for being "late + slow to develop" despite the rulebook calling a reclaim an
automatic S.

- **done-when:** all five original clauses plus clauses 5–10 and the reclaim-speed line
  are in `Trading-Bot-Rulesets.md`, each naming at least one mark id, and the file still
  parses as the same document (no sections deleted).
- **verify:**
  ```bash
  python -c "
  s=open('Trading-Bot-Rulesets.md').read()
  low=s.lower()
  need=('closes beyond the stop','close, except','09:30','session extreme','2 attempts','displacement','consolidation','in-between mesh','pivot structure','s+','confluence','reclaim speed','not yet implemented')
  miss=[k for k in need if k not in low]
  assert not miss, 'missing clause: %s' % miss
  ids=('MSTR_2024-09-26_11_14','AMD_2025-03-28_31','INTC_2025-02-27_72_153','CRM_2024-11-11_14','GOOGL_2026-01-20_67','MSFT_2025-03-20_28','AAPL_2024-10-28_162','AMZN_2025-07-17_34','PLTR_2025-12-10_45_52')
  noid=[m for m in ids if m not in s]
  assert not noid, 'missing evidence id: %s' % noid
  print('rulebook OK')
  "
  ```


### T10 -- Pivot structure as a first-class level
- model: opus

The engine knows exactly six levels — OR high, OR low, PDH, PDL, PMH, PML — plus order
blocks and the session HOD/LOD. Austin confirmed 2026-08-11 that his eye also trades
**pivot structure**: swing highs and lows built from price itself. His notes say it
outright and repeatedly: *"pivot-structure break > level break"* (`AMZN_2025-07-17_34`),
*"no clean break it just respect pivot structures so maybe higher timeframe thesis"*
(`NVDA_2024-09-06_53`), *"break/retest of a 2-candle structure, not a large pivot"*
(`TSLA_2024-12-03_17`), *"I would raise the stop after the second time to the higher
piece of the pivot structure"* (`NVDA_2025-11-28_14_22`), *"dont see any levels, unless
some were forgot to be marked"* (`SPY_2024-06-11_23`).

**If this is real, it is the ceiling on everything else** — a detector blind to the level
a trade is keyed to cannot be filtered into agreement, only filtered into silence.

Add a `pivot_levels(candles, ...)` source in `signal_runner.py` alongside the existing
level builders. A pivot high is a bar whose high exceeds the highs of the `PIVOT_STRENGTH`
bars either side of it; mirror for a pivot low. Expose `PIVOT_STRENGTH` as an
env-overridable constant (start at 2 — a 2-bar swing on each side, which is the smallest
structure Austin's "2-candle structure" note treats as real) and emit each pivot as a
level with `stop_level_name` of the form `pivot high @HH:MM` / `pivot low @HH:MM` so
`idea_key()` and `_targets_session_extreme()` keep working unchanged.

Only pivots formed **before** the signal bar may be used — a pivot needs
`PIVOT_STRENGTH` bars to its right to exist, so a pivot is only usable from
`pivot_index + PIVOT_STRENGTH + 1` onward. Getting this wrong is lookahead and would
make every downstream number a fiction; assert it in the tests.

Feed pivot levels into break-and-retest detection exactly as named levels are fed today.
Austin's *"pivot-structure break > level break"* means a B&R off a pivot ranks **above**
one off a named level when both are present on the same bar — record that ordering in the
signal so T11 can use it, do not silently prefer one.

Then measure: replay detection over `research/austin_marks_v7.jsonl` with pivots off and
on, and write `research/t10_pivot_levels.md` with these exact lines plus a table of which
previously-unexplained Austin S marks a pivot level now accounts for:

```
s_marks_total: <n>
s_explained_before: <n>
s_explained_after: <n>
pivot_fires_per_day: <float>
```

`s_explained` = an Austin S mark where the engine now emits any signal within 2 bars of
his marked entry. If `s_explained_after` is not greater than `s_explained_before`, say so
plainly in the report — a negative result here is a real finding and must not be dressed up.

- **done-when:** `pivot_levels` exists and is env-tunable, pivots are provably not visible
  before they complete, break-and-retest consumes them, and the before/after report is
  written with all four lines.
- **verify:**
  ```bash
  python -m py_compile signal_runner.py
  python test_austin_tier.py 2>&1 | tee /tmp/t10_tests.txt
  test $? -eq 0
  ! grep -q 'FAIL\|Traceback' /tmp/t10_tests.txt
  python -c "
  import signal_runner as sr
  assert callable(getattr(sr,'pivot_levels',None)), 'pivot_levels missing'
  assert hasattr(sr,'PIVOT_STRENGTH'), 'PIVOT_STRENGTH missing'
  from collections import namedtuple
  C=namedtuple('C','timestamp open high low close volume')
  bars=[C('09:%02d:00'%(30+i),1,h,h-1,h,100) for i,h in enumerate([5,6,9,6,5,4,3,4,5,8,5,4,3])]
  lv=sr.pivot_levels(bars)
  assert lv, 'no pivots found in a series with an obvious swing high'
  idx=[getattr(l,'index',l.get('index') if isinstance(l,dict) else None) for l in lv]
  assert all(i is not None for i in idx), 'pivot levels must carry the bar index they formed on'
  print('pivot_levels OK,', len(lv), 'pivots')
  "
  python -c "
  import re
  r=open('research/t10_pivot_levels.md').read()
  need=['s_marks_total','s_explained_before','s_explained_after','pivot_fires_per_day']
  miss=[k for k in need if not re.search('^'+k+r':\s*[0-9.]+', r, re.M)]
  assert not miss, 'missing: %s' % miss
  print('pivot report OK')
  "
  ```


### T11 -- Give S a quality bar it has to earn
- model: opus
- depends-on: T3, T7, T10

Today `compute_austin_tier` grants S to any bar where clause 1 holds (the setup is one of
the three) and three *negative* filters do not fire. There is no positive quality test
anywhere, which is why the engine emits 74,805 break-and-retests while Austin takes 1–3 S
a day. This row inverts that: S must earn its way past quality clauses.

**(a) Arm the two dormant quality levers.** `BNR_DISPLACEMENT_GATE` (line 140) and
`RULE_710_ENABLED` (line 280) are fully coded, default `False`, and are exactly the
displacement and retest-speed/pivot-count rules Austin has been writing in his notes.
Default both to **on**. Make the displacement gate implement the definition T7 writes into
`Trading-Bot-Rulesets.md` — read that paragraph, do not invent a threshold.

**(b) A/B the two levers that are fitted or unsettled, do not arm them blind.** `S_GATE`
(line 212) was fit to a 50th percentile of X-marks and never A/B'd; `HTF_OPPOSITION_VETO`
is hard-coded to `"hard"` while three of Austin's notes say a good fill should override an
opposed higher timeframe. Measure both arms of each against
`research/austin_marks_v7.jsonl` and report; leave the defaults as they are unless the
measurement is decisive, and say which way it went.

**(c) In-between mesh becomes a hard S-veto.** Austin, 2026-07-06: "middle of a bunch of
levels, probability goes down significantly", and 2026-08-11 he made it a veto rather than
a demotion. An entry with another known level (including the new pivot levels from T10)
sitting between it and its 2R target, with no clear room, cannot be S. `LEVEL_BLOCK_CAP`
already computes something close to this for the engine *grade* — reuse that computation,
do not duplicate it, and route it into `compute_austin_tier` where it currently has no
effect.

**(d) Confluence flag.** When two of the three setups fire on the same symbol, direction
and bar, set `confluence: true` on the signal and record which pair. Reported, never
required — a lone clean setup is still S.

**(e) S+ ranking.** All S signals stay S; this is a rank, not a new tier letter, and
nothing is discarded. Add `s_rank` to each S signal: the top **1–3 per day universe-wide**
are `"S+"`, everything else `"S"`. Rank earliest-first — Austin: "the top s trades which
usually happen earlier in the day" — breaking ties by engine grade then by confluence.
Cap at 3 per calendar day across all symbols, env-overridable as `S_PLUS_PER_DAY`.

Then write `research/t11_s_quality.md` with these exact lines:

```
s_fires_per_day_before: <float>
s_fires_per_day_after: <float>
s_plus_per_day: <float>
s_precision_before: <pct>
s_precision_after: <pct>
mesh_vetoed: <n>
confluence_bars: <n>
```

`s_precision` = share of the engine's S bars that Austin graded S in v7. The target rate
Austin gave is **1–3 S+ per day across the 15 symbols**; if `s_fires_per_day_after` is
still in the hundreds, say so plainly — that is the finding, not a failure to hide.

- **done-when:** both quality levers default on, mesh vetoes S, confluence and `s_rank`
  are set on signals, `s_plus_per_day` is at most 3, and the report carries all seven lines.
- **verify:**
  ```bash
  python -m py_compile signal_runner.py
  python test_austin_tier.py 2>&1 | tee /tmp/t11_tests.txt
  test $? -eq 0
  ! grep -q 'FAIL\|Traceback' /tmp/t11_tests.txt
  python -c "
  import signal_runner as sr
  assert sr.BNR_DISPLACEMENT_GATE is True, 'displacement gate not armed'
  assert sr.RULE_710_ENABLED is True, 'rule 7/10 not armed'
  assert hasattr(sr,'S_PLUS_PER_DAY'), 'S_PLUS_PER_DAY missing'
  assert sr.S_PLUS_PER_DAY <= 3, sr.S_PLUS_PER_DAY
  body=open('signal_runner.py').read()
  for k in ('mesh','confluence','s_rank'):
      assert k in body, 'missing '+k
  print('S quality bar OK')
  "
  python -c "
  import re
  r=open('research/t11_s_quality.md').read()
  need=['s_fires_per_day_before','s_fires_per_day_after','s_plus_per_day','s_precision_before','s_precision_after','mesh_vetoed','confluence_bars']
  miss=[k for k in need if not re.search('^'+k+r':\s*[0-9.]+', r, re.M)]
  assert not miss, 'missing: %s' % miss
  sp=float(re.search(r'^s_plus_per_day:\s*([0-9.]+)', r, re.M).group(1))
  assert sp<=3.0, 'S+ rate %s exceeds the 1-3/day target' % sp
  print('S quality report OK')
  "
  ```


### T8 -- Backtest BR/OCR and the 84% rule separately, per pool
- model: glm
- depends-on: T1, T3, T4, T5, T10, T11

Austin: "lets seperate OCR BR from 84 percent rule in backtesting because those two seem
closer to understood." Today the backtest reports one blended number, so a change that
helps BR and hurts the 84% rule is invisible.

Run the 12-month backtest on the post-T3/T4 engine and write
`research/t8_split_backtest.md` reporting **three independent books**, each with its own
trade count, win rate, total P&L and average R:

- `BR_OCR` — break-and-retest plus one-candle-rule entries only
- `RULE84` — 84%-rule re-entries only
- `COMBINED` — both, for comparison with the old single number

and each of those broken out by pool (`MAJOR_15`, `INDEX_POOL`, `OTHER_POOL`) using
`universe.POOL_OF`. Use these exact line formats so the numbers are greppable:

```
br_ocr_trades: <n>
br_ocr_winrate: <pct>
br_ocr_pnl: <dollars>
rule84_trades: <n>
rule84_winrate: <pct>
rule84_pnl: <dollars>
combined_trades: <n>
combined_winrate: <pct>
combined_pnl: <dollars>
```

On top of that, report the **S+ book on its own** — the 1–3/day top-ranked S signals T11
produces — because that is the book Austin would actually trade. Same four numbers, plus
these exact lines:

```
s_plus_trades: <n>
s_plus_winrate: <pct>
s_plus_pnl: <dollars>
s_all_winrate: <pct>
```

**Walk it forward in the same run.** Every number above is in-sample, and a prior
walk-forward on a different engine version lost 6–10 points going out of sample — an
in-sample-only report is how the last three versions produced numbers that did not survive
contact. Split the archive by date at the 70th percentile of trading days: everything T11
tuned (`SESSION_EXTREME_FRAC`, the `S_GATE` / `HTF_OPPOSITION_VETO` arms) is chosen on the
first 70% only, then the last 30% is scored once, untouched. Report:

```
s_plus_winrate_is: <pct>
s_plus_winrate_oos: <pct>
br_ocr_winrate_is: <pct>
br_ocr_winrate_oos: <pct>
oos_days: <n>
```

State plainly whether `s_plus_winrate_oos` clears Austin's 55% target — **that is the only
win-rate number in this spec that means anything**, and if it comes in under, say so
without softening. Also state whether the 84% book is additive or dilutive to
`combined_pnl`.

- **done-when:** the report exists with all nine lines above plus a per-pool table, and
  the three books' trade counts add up (`br_ocr_trades + rule84_trades == combined_trades`).
- **verify:**
  ```bash
  python -c "
  import re
  r=open('research/t8_split_backtest.md').read()
  g=lambda k: re.search('^'+k+r':\s*\\\$?(-?[0-9.]+)', r, re.M)
  need=['br_ocr_trades','br_ocr_winrate','br_ocr_pnl','rule84_trades','rule84_winrate','rule84_pnl','combined_trades','combined_winrate','combined_pnl','s_plus_trades','s_plus_winrate','s_plus_pnl','s_all_winrate','s_plus_winrate_is','s_plus_winrate_oos','br_ocr_winrate_is','br_ocr_winrate_oos','oos_days']
  miss=[k for k in need if not g(k)]
  assert not miss, f'missing: {miss}'
  assert int(float(g('oos_days').group(1)))>=60, 'out-of-sample window too small to mean anything'
  a,b,c=(int(float(g(k).group(1))) for k in ('br_ocr_trades','rule84_trades','combined_trades'))
  assert a+b==c, '%d+%d != %d' % (a,b,c)
  assert a>0, 'BR/OCR book is empty'
  nopool=[p for p in ('MAJOR_15','INDEX_POOL','OTHER_POOL') if p not in r]
  assert not nopool, 'missing pool: %s' % nopool
  print('split backtest OK')
  "
  ```


### T9 -- Measure eye-to-eye agreement per setup on the new engine
- model: glm
- depends-on: everything

Austin's target is 95% agreement with the bot's S calls on BR, OCR and the 84% rule,
scored **separately** — never blended. As of 2026-08-11 the measured numbers are
84%-rule 5.0% S-precision, OCR 0.0%, BR 0.0% on 80 blind cards.

Replay the post-T3/T4 engine over every `(symbol, day)` in
`research/austin_marks_v7.jsonl` restricted to `universe.MAJOR_15`, and for each of the
three setups build the confusion between Austin's tier and the engine's tier at the same
bar. Score **exact tier match**, with X–X counted as agreement (the bot correctly
declining a trade Austin also declines is agreement). Denominator is every graded row,
not just the ones the engine fired on.

Write `research/t9_eye_match.md` with these exact lines:

```
br_match: <pct>
br_n: <n>
ocr_match: <pct>
ocr_n: <n>
rule84_match: <pct>
rule84_n: <n>
```

plus the same three for the **S+ subset only**, as `br_match_splus:` / `ocr_match_splus:`
/ `rule84_match_splus:` — Austin cares most about the S rules, so the S+ number is the
headline and the all-S number is context.

Then, for each setup, the top disagreement modes ranked by count — engine fired where
Austin said X, engine silent where Austin said S, tier off by one — with example ids.
Also report `before` numbers from the pre-T3/T4 engine on the same rows so the delta from
this version is visible, as `br_match_before:` / `ocr_match_before:` / `rule84_match_before:`.

Do not stop at reporting: name in one paragraph the single largest remaining
disagreement mode and what rule change would close it. That paragraph is the seed for
omen-5.1.

- **done-when:** the report exists with all six current lines and all three `_before`
  lines, each `_n` is at least 15, and every percentage is a real number computed from
  v7 rather than a placeholder.
- **verify:**
  ```bash
  python -c "
  import re
  r=open('research/t9_eye_match.md').read()
  g=lambda k: re.search('^'+k+r':\s*(-?[0-9.]+)', r, re.M)
  need=['br_match','br_n','ocr_match','ocr_n','rule84_match','rule84_n','br_match_before','ocr_match_before','rule84_match_before','br_match_splus','ocr_match_splus','rule84_match_splus']
  miss=[k for k in need if not g(k)]
  assert not miss, 'missing: %s' % miss
  small=[k for k in ('br_n','ocr_n','rule84_n') if int(float(g(k).group(1)))<15]
  assert not small, 'sample too small: %s' % small
  bad=[k for k in ('br_match','ocr_match','rule84_match') if not 0<=float(g(k).group(1))<=100]
  assert not bad, 'percentage out of range: %s' % bad
  print('eye-match OK')
  "
  ```

# VOID 2026-08-03 - do not run

loop-ci runs on `ubuntu-latest` cloud runners (`loop.yml:24,71,127`). Every row in this
spec needs local ollama - moondream, nomic-embed-text, qwen3:4b - plus
`rule_ledger_v2.jsonl` and the image dirs. The ledger is untracked and
`discord_data/images/`, `youtube_data/`, `circle_data/` are gitignored, so none of it ever
leaves the PC. The runner would check out tradingbot, find no data and no ollama, and burn
seven rows failing.

T6 is void for a second reason. `vision_extract.py` never called a model: it is a keyword
if/elif chain, its `route` field is a string literal written into the record, and its 232
rows came from 3 frames (4 templates x 3 windows x 3 offsets, routes split 58/58/58/58).
It was not a paid pipeline that stalled - it was never built.

Replaced by `TradingBot\research\RUNBOOK-omen-3.1.md`, run at the PC.

---

# OMEN 3.1 - Cluster the ledger, finish the triage, mine the keeper frames

status: ready
version: omen-3.1
repo: aharger3/tradingbot

target: the 34,695-record extraction finished 8/3 19:41 and nothing consumed it. Turn 32,956 distinct rule texts into a readable clustered index, finish the 10,001 untriaged images, and pull setup records out of the 2,796 keeper frames that were classified but never extracted. Every model call in this version is local ollama. Cost is GPU hours, not dollars.

## Tasks

### T1 -- Resume vision triage on the ~10,001 untriaged images

- model: deepseek

`vision_triage.py` in the repo root classifies images with local `moondream:latest` over ollama at `http://localhost:11434/api/generate`. It is checkpointed: it writes `C:\Users\aharg\Desktop\loop\vision_triage_manifest.json` with a `frames` dict keyed by manifest key and a `stats` dict, and it skips any key already present.

Current manifest: 27,523 entries, stats `{total: 27523, chart-with-annotation: 3028, chart-plain: 1, junk: 24494}`. By source: 8,323 youtube frames (complete), 6,140 discord (of 6,636), 13,060 scarface (of 22,565).

Run it to completion. `cd C:\Users\aharg\Desktop\projects\tradingbot` first, and `set PYTHONIOENCODING=utf-8` before the python call. Do not change `FRAMES_DIR` key handling â€” youtube frames use bare relative keys and re-prefixing them would re-triage all 8,323.

If the run dies partway, re-run it; the manifest skip makes it resumable. Append one timestamped line per 500 images to `research\vision_triage3.log` so a stalled run is distinguishable from a finished one.

- **done-when:** `python -c "import json;d=json.load(open(r'C:\Users\aharg\Desktop\loop\vision_triage_manifest.json'));print(d['stats']['total'])"` prints a number >= 37000, and `research\vision_triage3.log` exists with a final line containing `DONE`.

### T2 -- Embed the 32,956 distinct rule texts with nomic-embed-text

- model: deepseek

Write `research\embed_rules.py`. Read `research\rule_ledger_v2.jsonl` (34,695 lines, keys `chunk_id, source, id, text, predicate, citation, setup, scope, confidence, novel, _no_rules`). Dedup on `re.sub(r'\W+',' ',text.lower()).strip()` â€” that yields 32,956 distinct texts, 3.46M chars.

Embed each distinct text with local `nomic-embed-text:latest` via `POST http://localhost:11434/api/embeddings` with `{"model":"nomic-embed-text:latest","prompt":text}`. Send a User-Agent header. Batch and checkpoint every 500 embeddings to `research\rule_embeddings.npy` (float32, shape `(n, 768)`) plus `research\rule_ids.json` (list of `{"key":normalised, "id":ledger_id, "text":original, "source":source, "setup":setup, "confidence":confidence}` in the same row order as the npy). On restart, load both and skip what is already embedded.

`set PYTHONIOENCODING=utf-8`. Python 3.13 system interpreter, not the hermes venv.

- **done-when:** `python -c "import numpy,json;a=numpy.load(r'research\rule_embeddings.npy');ids=json.load(open(r'research\rule_ids.json'));assert a.shape[0]==len(ids)==32956,(a.shape,len(ids));assert a.shape[1]==768;print('OK',a.shape)"` prints `OK (32956, 768)`.

### T3 -- Cluster the embeddings

- model: deepseek
- depends-on: T2

Write `research\cluster_rules.py`. Load `research\rule_embeddings.npy` and `research\rule_ids.json` written by T2. L2-normalise the rows, then greedy-cluster by cosine similarity: walk rules in descending order of how many ledger records share their normalised key (most-repeated first), and for each unassigned rule open a new cluster and pull in every unassigned rule with cosine >= 0.86. Do the similarity in chunks of 2,000 rows so a 32,956 x 32,956 matrix is never materialised.

Write `research\rule_clusters.json`: a list of `{"cluster_id": int, "size": int, "n_records": int, "sources": [distinct source values], "exemplars": [the 5 member texts closest to the cluster centroid], "member_ids": [...]}`, sorted by `n_records` descending.

0.86 is a starting threshold, not a law. Print the cluster count and the size of the largest cluster. If the count comes out above 8,000 the threshold is too tight and if it comes out below 200 it is too loose â€” in either case re-run at 0.90 or 0.82 respectively and keep the run that lands in range. Write the threshold actually used into the JSON as a top-level `"threshold"` key alongside the clusters.

Write `research\test_cluster_rules.py` asserting: every id in `rule_ids.json` appears in exactly one cluster's `member_ids`; no cluster is empty; `sum(len(c["member_ids"]))` equals 32,956.

- **done-when:** `python research\test_cluster_rules.py` prints `ALL PASS`, and `python -c "import json;d=json.load(open(r'research\rule_clusters.json'));c=d['clusters'];print(len(c));assert 200<=len(c)<=8000"` prints a number in range.

### T4 -- Name the top 300 clusters with local qwen3:4b

- model: deepseek
- depends-on: T3

Write `research\name_clusters.py`. Take the first 300 clusters from `research\rule_clusters.json` by `n_records`. For each, send its 5 exemplars to local `qwen3:4b` via `POST http://localhost:11434/api/generate` with `{"stream": false}` and a User-Agent header, asking for two things back as JSON: a one-sentence canonical statement of the rule these five are all saying, and a bucket from exactly this set â€” `B&R`, `order block`, `84%`, `X-reject`, `entry-timing`, `risk`, `regime`, `other`.

Note the buckets are wider than the four in `rebuild_rules_index.py`. That is deliberate: the old regex bucketing dumped 21,647 of 28,405 rules into `candidate`, so the taxonomy, not the data, was the problem.

Write `research\rule_cards.jsonl`, one line per named cluster: `{"cluster_id", "canonical", "bucket", "n_records", "size", "sources", "exemplars"}`. Checkpoint after every cluster so the run resumes. If a model reply does not parse as JSON, retry once, then write the row with `"bucket": "other"` and `"canonical"` set to the longest exemplar, and count it â€” do not let one bad reply stop the run.

No paid model. qwen3:4b is local and free; if its output is unusable that is a finding for the report in T7, not a reason to route out.

- **done-when:** `python -c "import json;rows=[json.loads(l) for l in open(r'research\rule_cards.jsonl',encoding='utf-8')];print(len(rows));assert len(rows)>=300;assert all(r.get('canonical') and r.get('bucket') for r in rows)"` prints a number >= 300.

### T5 -- Rewrite rules_index.md from the clusters

- model: deepseek
- depends-on: T4

`research\rules_index.md` is currently 28,470 lines / 2.3MB because `rebuild_rules_index.py` dedups on exact normalised text â€” it collapsed 29,176 rules to 28,405 (2.6%) and found exactly 1 multi-source rule. That file is a dump, not an index.

Write `research\rebuild_rules_index_v2.py`, reading `research\rule_cards.jsonl` and `research\rule_clusters.json`. Keep the three header sections of the current index (Corpus Overview, Signal Rate by Source, bucket summary table) â€” the per-source signal rates are worth keeping â€” but replace the body with one table per bucket whose rows are clusters, not raw rules: rank, `n_records`, distinct source count, canonical statement, cluster_id. Sort within each bucket by distinct source count, then `n_records`.

Corroboration is now the count of distinct `source` values among a cluster's members, which is the number the old exact-text dedup could not produce.

Overwrite `research\rules_index.md`. Leave `rebuild_rules_index.py` on disk untouched.

- **done-when:** `python -c "ls=open(r'research\rules_index.md',encoding='utf-8').read().splitlines();print(len(ls));assert len(ls)<3000"` prints a number under 3000, and `python -c "import re;t=open(r'research\rules_index.md',encoding='utf-8').read();n=len(re.findall(r'\|\s*[23]\s*\|',t));print('multisource rows',n);assert n>50"` prints a count above 50.

### T6 -- Extract setup records from the 2,796 unprocessed keeper frames

- model: deepseek
- depends-on: T1

`vision_extract.py` in the repo root turns a `chart-with-annotation` frame plus its +/-15s transcript window into a structured record â€” `pattern`, `entry_trigger`, `stop_logic`, `target_logic`, `context_regime`, `quote`. It ran once on 2026-07-27 and produced 232 rows in `research\vision_setups.jsonl`. The triage manifest holds 3,028 keepers as of T1's start and more after T1 finishes, so roughly 2,796+ have never been through it.

Two things to fix before running it:

Its `TRIAGE_MANIFEST` and `OUTPUT_FILE` constants point at `C:/Users/aharg/Desktop/loop/...`. The manifest genuinely lives at `C:\Users\aharg\Desktop\loop\vision_triage_manifest.json` so that path is correct and stays. The output must be written to `C:/Users/aharg/Desktop/projects/TradingBot/research/vision_setups.jsonl`, which is where the existing 232 rows already are and where `build_worklists.py` and `research\circle_ingest.py` read from. Change `OUTPUT_FILE` to that path.

Its `ROUTE_OPTIONS` list starts with `claude`, which is what made this expensive and is why it stopped after 232 rows. Add a route that calls local `qwen3:4b` over ollama and make it the default. The record fields are derived from the transcript window text, so a text model is the right tool; the frame's classification already came from moondream in T1.

Make it skip any `source_frame` already present in `vision_setups.jsonl` so the 232 existing rows are not redone and the run is resumable. Append one timestamped progress line per 100 frames to `research\vision_extract2.log`.

- **done-when:** `python -c "rows=[l for l in open(r'research\vision_setups.jsonl',encoding='utf-8') if l.strip()];print(len(rows));assert len(rows)>=2000"` prints a count of at least 2000, and no row's `route` field is `claude`.

### T7 -- Write the version report

- model: deepseek
- depends-on: everything

Write `research\omen_v3.1_report.md`. Pull the numbers off disk, do not restate this spec:

- triage totals from `C:\Users\aharg\Desktop\loop\vision_triage_manifest.json` `stats`, before and after â€” before was `{total: 27523, chart-with-annotation: 3028, junk: 24494}`
- cluster count and threshold used from `research\rule_clusters.json`
- bucket distribution from `research\rule_cards.jsonl`, and specifically how many landed in `other` â€” a high `other` count means qwen3:4b could not name the clusters and the naming step needs a better model next version
- the top 20 clusters by distinct source count, with their canonical statements â€” this is the actual output of the version
- setup record count from `research\vision_setups.jsonl`, before (232) and after
- line count of `research\rules_index.md`, before (28,470) and after

Then one section titled `Recommended next version` with a single recommendation and the evidence for it. Do not start it.

Last: `git add` the new scripts, the report, `research\rules_index.md`, `research\rule_cards.jsonl`, `research\rule_clusters.json`, `research\vision_setups.jsonl` and commit on branch `wip/v3-carryover`. Do not commit `research\rule_embeddings.npy` â€” it is large and regenerable from T2.

- **done-when:** `research\omen_v3.1_report.md` exists, contains the string `Recommended next version`, and `git log -1 --oneline` shows a new commit.

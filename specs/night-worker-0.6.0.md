# NIGHT-WORKER 0.6.0 - Never idle, always reports, taps not typing

status: done
version: night-worker-0.6.0
repo: aharger3/night-worker
doc: Projects/night-worker.md

target: Make the box run unattended and make a short night impossible to miss -  for a full 23h from a launch at any hour - work never runs out, every model call has an OmniRoute rung under it, the 08:00 report always fires and carries tappable numbered options, silence by 09:00 picks the recommendation itself, and only a block a physical agent genuinely cannot clear interrupts the day.

## Settled in the 2026-08-18 grilling - never re-elicit

1. **Work supply is a depth-first backlog with an infinite floor.** The worker walks the
   fixed catalog in priority order. When the real queue drains it falls to
   `discord_regrade` (10,379 instances). No model invents a task type - that was the v1
   failure and it stays closed.
2. **Anytime-start window.** `worker.ps1 -Until 08:00` runs from whenever it is launched to
   the next 08:00. A 15:21 kick is a 16h39m night. No new scheduled task, no cron - the
   existing `\NightWorker` triggers stay exactly as they are.
3. **OmniRoute is the fallback on every model stage, per call. Gemini is removed.**
   Ollama first; an empty or erroring call retries once on a pinned OmniRoute provider;
   a second failure logs the row failed and moves on. No free-tier quota paces this box
   again.
4. **The 08:00 report is unconditional.** A night with nothing to say still posts - an
   absent message and a dead worker must never look alike.
5. **Numbered recommendations get keycap reactions.** `brief.py` posts, then adds
   1..N as keycap emoji. Tap one, or type the number in-thread; both are read.
6. **night-worker reads its own taps - responder is not touched.** Responder already does
   the `:eyes:` receipt on typed replies. Reading a reaction needs one `reactions.get`
   call against a ts night-worker already owns, which is strictly less work than teaching
   another daemon a new job. Nothing in `aharger3/responder` changes in this version.
7. **09:00 silence = the recommendation runs**, and `assumed: <n>` is written into the log
   and into the vault note so the assumption is visible, never silent.
8. **Daytime pushes are for hard blocks only** - something a physical agent cannot do:
   a login or cookie wall, an expired API key or MCP link, hands on the box, money or a
   decision, or a stage the supervisor abandoned after 3 heals. Everything else waits for
   08:00.

## What must not change

- `think = false` on every Ollama call, `num_ctx = 16384`, `OLLAMA_MAX_LOADED_MODELS=1`.
- **Every `.ps1` copied to the box must be ASCII-only.** Non-ASCII becomes a parse error there.
- No model reports its own success. Every row is judged by the file it wrote.
- No new scheduled task, no cron, no schedule changes of any kind.
- Slack channel is `C0BQK5RUXL2`; ntfy topic is `aharg-nw` and carries alarms only.


### [x] T1 -- Anytime-start window: `worker.ps1 -Until`
- model: glm

`worker.ps1` today assumes it was started by the 09:00 trigger and computes its stop from
that assumption. Replace it with an explicit window.

Add a `[string]$Until = "08:00"` parameter. On start, compute `$stopAt` as the next
occurrence of that wall-clock time strictly after `Get-Date` - so a 15:21 launch stops at
tomorrow 08:00, and a 07:00 launch stops at 08:00 today. Log one `window` row to
`night-log.jsonl` at start carrying `start`, `stop` and the computed duration in minutes.
Every existing stop check must read `$stopAt` instead of recomputing a hardcoded 08:00.

Keep the single-instance `worker.lock` PID check exactly as it is - an anytime start must
still refuse to run twice.

Add `tests/test_window.ps1`: dot-source the window helper (extract it as
`Get-StopTime([datetime]$now, [string]$until)` so it is callable without starting a run) and
assert three cases - 15:21/08:00 gives tomorrow 08:00, 07:00/08:00 gives today 08:00, and
exactly 08:00/08:00 gives tomorrow 08:00. Exit 1 on any mismatch.

- **done-when:** `pwsh tests/test_window.ps1` exits 0 and `worker.ps1` accepts `-Until`.
- **verify:**
  ```bash
  pwsh tests/test_window.ps1
  pwsh tests/parse-ps1.ps1
  grep -q 'Get-StopTime' worker.ps1
  ```


### [x] T2 -- One LLM call path: Ollama first, OmniRoute second, Gemini gone
- model: glm

Model calls are scattered - `stagec.py` has `ollama_vision()` and `gemini()`, `worker.ps1`
stage B calls Ollama inline with its own model name, and the two disagree on which model is
current. Collapse them.

Create `llm.py` exporting one function:

```
call(model, prompt, images=None, timeout=120) -> str
```

It POSTs to `http://localhost:11434/api/generate` with `"think": false` at the top level and
`options: {"num_ctx": 16384}`. If the HTTP call raises, or the response's `response` field is
empty or whitespace, retry the identical request **once** against OmniRoute. Pin the
provider per `Projects/homelab.md` - base URL `https://openrouter.ai/api`, provider order in
`CLAUDE_CODE_EXTRA_BODY`-style extra body, key read from the `OPENROUTER_KEY` environment
variable or `.openrouter-key` beside the script. A bare model id is not a route; the pinned
form is the only accepted form. If OmniRoute also fails or returns empty, raise
`LlmFailed(model, reason)` - callers log the row failed and continue to the next row. Never
raise past the row.

Log one `llm` row to `night-log.jsonl` per call with `model`, `rung` (`local` or `omni`) and
`ms`, so the morning report can show how often the local card was enough.

Rewrite `stagec.py` to call `llm.call(...)` and **delete `gemini()`, `GEMINI_SLEEP`, and
every read of `GEMINI_KEY`**. Also delete the key file read if one exists. Stage B in
`worker.ps1` must call the same path via `python -c` or a thin `stageb.py` rather than
keeping its own hardcoded model string; the model name for each stage lives in one dict at
the top of `llm.py` (`STAGE_MODELS = {"caption_extract": "qwen3.5:4b", "frame_ocr": "qwen2.5vl:3b"}`)
and nowhere else.

Add `tests/test_llm.py` (pytest) with a fake transport injected as a parameter - not
monkeypatched globals - covering: local ok returns text and logs `rung: local`; local empty
falls to omni and logs `rung: omni`; both empty raises `LlmFailed`.

- **done-when:** `python -m pytest tests/test_llm.py -q` passes and no file in the repo
  mentions Gemini.
- **verify:**
  ```bash
  python -m pytest tests/test_llm.py -q
  test -z "$(grep -ril gemini --include='*.py' --include='*.ps1' . )"
  grep -q 'STAGE_MODELS' llm.py
  grep -q 'openrouter.ai/api' llm.py
  ```


### [x] T3 -- The queue never drains: depth-first backlog with an overflow floor
- model: glm

The night can currently run out of work and spin. Build the supply.

Create `queue.py` exporting `next_rows(n=50) -> list[dict]`. It walks the catalog in this
fixed priority order and returns the first `n` rows that are genuinely pending:

```
1 yt_captions       videos in the worklist with no caption file
2 caption_extract   caption files with no extract row
3 yt_frames         extracts that yielded a setup and have <3 PNGs
4 frame_ocr         PNGs with no corpus_frames row
5 embed             corpus rows not yet in the index
6 discord_regrade   OVERFLOW FLOOR - instances in corpus_instances.jsonl
                    not labeled under the current rules
```

Rows 1-5 are computed by comparing files on disk, not by trusting any state file, so a
half-finished night resumes correctly. Row 6 is the floor: it is only reached when 1-5
return nothing, and it must always return work while unlabeled instances remain.

`next_rows` must never return an empty list while any pending work exists at any tier. If
every tier including the floor is genuinely exhausted, return `[]` and let the caller log a
`drained` row - that is the only legitimate idle state and it is a reportable event, not a
silent one.

Wire `worker.ps1`'s main loop to refill from `queue.py` whenever its in-memory batch empties,
instead of walking a single stage to completion. Log a `refill` row with the tier name each
time, so the report can say which tier the night spent its hours in.

Add `tests/test_queue.py` building a temp directory tree that exercises the ladder:
assert tier 1 wins when captions are missing; assert the floor is returned when tiers 1-5
are satisfied but unlabeled instances remain; assert `[]` only when everything including
the floor is exhausted.

- **done-when:** `python -m pytest tests/test_queue.py -q` passes and the floor case returns
  non-empty.
- **verify:**
  ```bash
  python -m pytest tests/test_queue.py -q
  grep -q 'discord_regrade' queue.py
  grep -q 'refill' worker.ps1
  ```


### [x] T4 -- The 08:00 report always posts, with tappable numbered options
- model: glm
- depends-on: T3

`brief.py` posts a report today but can be skipped and offers no tap target. Fix both.

**Unconditional.** The report posts even when the night did nothing - an empty night reads
`nothing ran` plus the reason, never silence. Wrap the whole body-building step so that any
exception still results in a posted message carrying the traceback's first line; a crashed
report must still be a posted report.

**Structure** - keep the existing sections and add the recommendation block last:

```
Night Worker  <YYYY-MM-DD>  <Nh Nm>
done:   <tier> <n> rows            (one line per tier touched)
broke:  <stage> <reason>           (include stages the supervisor abandoned)
rungs:  local <n> / omni <n>
blocks: <n open>                   (from T6's block file, or 'none')
what next
1. <recommended>
2. <alt>
3. <alt>
```

Recommendations are computed from `queue.py`, not written by a model: option 1 is the tier
`next_rows` would pick, options 2 and 3 are the next two distinct tiers with pending work.
Always emit exactly 3 options, padding from lower tiers so the numbering is stable.

**Reactions.** After `chat.postMessage` returns the ts, call `reactions.add` once per option
with `one`, `two`, `three`. If a `reactions.add` call fails, log it and continue - a missing
keycap must never lose the report.

Write `Areas/Daily/night-brief.md` in the vault with frontmatter carrying `thread_ts`,
`channel`, `date` and an `options:` list of the three recommendation strings, so the 09:00
decision step in T5 reads what was offered rather than recomputing it.

Add `tests/test_brief.py` with a fake Slack client: assert a post happens when the log is
empty; assert exactly three `reactions.add` calls with `one`/`two`/`three`; assert the
written markdown contains `thread_ts:` and three `options:` entries.

- **done-when:** `python -m pytest tests/test_brief.py -q` passes, including the empty-night case.
- **verify:**
  ```bash
  python -m pytest tests/test_brief.py -q
  grep -q 'reactions.add' brief.py
  grep -q 'thread_ts' brief.py
  ```


### [x] T5 -- 09:00: read the tap, read the thread, or assume option 1
- model: opus
- depends-on: T4

This row decides what the box does with its next 23 hours on no human input, so a wrong
answer here silently wastes a day. It gets the careful model.

Create `decide.py`. It reads `Areas/Daily/night-brief.md` frontmatter for `thread_ts`,
`channel` and `options`, then resolves the choice in this precedence:

1. **Reaction.** `reactions.get` on that ts. A keycap `one`/`two`/`three` added by a user
   who is not the bot selects that option. If more than one keycap has a human reaction,
   take the **lowest** number and note the ambiguity in the log - never guess intent.
2. **Typed reply.** `conversations.replies` on that ts. The **first** human reply whose
   text starts with a bare digit 1-3 selects that option. A reply that is prose and not a
   digit is **not** a selection - it is recorded verbatim as `note:` in the log and the
   choice falls through to step 3. Free text is a message to a human, not a command.
3. **Assumption.** No reaction and no digit reply: select option 1.

Whatever is selected, write `night-queue.jsonl` naming the chosen tier, append a `decision`
row to `night-log.jsonl` carrying `source` (`reaction` / `reply` / `assumed`), `choice`, and
the option text, and post one short confirmation into the same thread reading
`running: <option text> (assumed)` when the source was an assumption. The word `assumed`
must appear both in the log row and in the vault note - a silent assumption is the failure
this row exists to prevent.

`decide.py` is invoked by `worker.ps1` at the start of a window, before the first refill -
not by a scheduled task. A window that starts at 15:21 runs it immediately with whatever
the last brief offered. If no `night-brief.md` exists, log `no-brief` and fall straight
through to `queue.py`'s own priority order - the absence of a decision must never stop work.

Add `tests/test_decide.py` with a fake Slack client covering all three precedence paths,
the multi-reaction tie (lowest wins), the prose-reply case (recorded as a note, still
assumed), and the missing-brief case.

- **done-when:** `python -m pytest tests/test_decide.py -q` passes all six cases and a run
  with no input writes a `decision` row whose source is `assumed`.
- **verify:**
  ```bash
  python -m pytest tests/test_decide.py -q
  grep -q 'assumed' decide.py
  grep -q 'reactions.get' decide.py
  grep -q 'decide.py' worker.ps1
  ```


### [x] T6 -- Hard blocks interrupt the day; nothing else does
- model: glm

Create `blocks.py` exporting `raise_block(kind, detail)` and the classifier that decides
what qualifies. Exactly five kinds are hard blocks - a thing a physical agent on the box
cannot clear by itself:

```
auth      login or cookie wall (yt-dlp login wall, Slack/OpenRouter 401)
key       an expired or missing API key, or a dead MCP link
hands     needs a human at the machine - reboot, USB, GUI-only click
money     paid quota or credit exhausted
abandoned a stage the supervisor gave up on after 3 self-heal attempts
```

Anything else - a single row failing, a flaky call that the OmniRoute rung recovered, a
video that is simply unavailable - is **not** a block. It is a log row and a line in the
08:00 report. Do not add a sixth kind.

`raise_block` appends to `blocks.jsonl` and, **only on the first occurrence of a given
(kind, detail) pair in this window**, posts to Slack `C0BQK5RUXL2` and fires an ntfy push to
`aharg-nw` with priority 4. The dedupe is what keeps a repeating auth failure from becoming
a hundred phone buzzes; hold the seen-set in the file itself so a restart does not re-notify.
Honour `NW_SLACK_DISABLE` and `NW_NTFY_DISABLE` exactly as the existing modules do.

Call it from the three places that can produce one: the caption ladder on a login wall, the
supervisor when it abandons a stage, and `llm.py` when OmniRoute returns 401 or a
credit-exhausted error.

Add `tests/test_blocks.py` with fake Slack and ntfy senders: assert all five kinds notify
once; assert a repeat of the same (kind, detail) does not notify twice; assert a plain row
failure produces no notification at all.

- **done-when:** `python -m pytest tests/test_blocks.py -q` passes and a duplicate block
  sends exactly one notification.
- **verify:**
  ```bash
  python -m pytest tests/test_blocks.py -q
  grep -q 'aharg-nw' blocks.py
  grep -c 'abandoned' blocks.py
  ```


### [x] T8 -- A short night is a failure, no matter what the exit code says

- model: glm
- depends-on: T3, T4

Measured on the box 2026-08-20, from `night-log.jsonl` worker start/stop pairs:

| Night | Ran for |
|---|---|
| 08-17 | 6h 09m |
| 08-18 | 2h 36m |
| 08-19 | 6m |
| 08-20 | **30 seconds** |

Every one of those runs exited 0, and `\NightWorker` reports `LastTaskResult 0`, State
`Ready`. The 08-20 run announced a 23-hour window, skipped all 217 already-done caption
rows, hit `stagec-drained`, and quit in thirty seconds. Nothing anywhere measures how long
the worker ran, so an idle night and a full night are the same green tick on every surface
that watches this system.

T3's overflow floor stops the box going idle. **This task makes it impossible for that
failure to ever again be invisible**, which is the separate and more important half.

**Measure the run.** `worker.ps1` already logs `stage=worker state=start` with
`detail="stop at <ISO>"` and a matching `state=stop`. On exit, compute
`ran_seconds = stop - start` and `window_seconds = until - start`, and write one final
line:

```json
{"stage":"worker","state":"summary","ran_seconds":<int>,"window_seconds":<int>,"rows_ok":<int>,"rows_failed":<int>}
```

Emit it from a `finally` block so it is written even when the worker throws. A run with no
`summary` line is itself the alarm.

**The floor.** `NW_MIN_RUN_FRACTION`, default **0.25**. A run is SHORT when
`ran_seconds < window_seconds * NW_MIN_RUN_FRACTION`, with an absolute floor of 900 seconds
so a deliberate short window is not permanently short. A fraction of the window, not a
fixed duration, because T2's anytime-start means the window is 2h some days and 23h others.

**A SHORT night is a hard block.** It routes through T6's block path with kind `idle`,
which means it pushes to `aharg-nw` the moment it is detected rather than waiting for
08:00. This is the one alarm that must not wait, because a short night means the next
23 hours are already being wasted.

**The report leads with it.** T4's header line becomes:

```
Night Worker  <YYYY-MM-DD>  ran <Nh Nm> of <Nh Nm>   <rows_ok>/<rows_failed>
```

and when the night was SHORT, the line directly under the header is:

```
SHORT NIGHT - ran <Nh Nm> of a <Nh Nm> window. Queue drained at <stage>.
```

That line goes above `done:`, above `broke:`, above everything. It is the single most
important fact the report can carry and it must never be below the fold.

**Backfill the history.** Add `nw_runlog.py` with `run_spans(path)` returning
`(start, stop, ran_seconds)` per worker start/stop pair in an existing `night-log.jsonl`,
so the trend above can be recomputed on demand rather than reconstructed by hand next time.

Add `tests/test_runfloor.py`: a 30-second run inside a 23-hour window is SHORT; a 6-hour
run in the same window is not; a 20-minute run inside a 30-minute window is not SHORT
because the 900-second absolute floor clears it; a log whose last worker pair has no
`summary` line is reported as SHORT rather than skipped; `run_spans` returns 4 spans for a
fixture holding 4 start/stop pairs.

- **done-when:** `python -m pytest tests/test_runfloor.py -q` passes, and running
  `python nw_runlog.py <fixture>` prints one line per span with its duration.
- **verify:**
  ```bash
  python -m pytest tests/test_runfloor.py -q
  grep -q 'NW_MIN_RUN_FRACTION' worker.ps1
  grep -q 'ran_seconds' worker.ps1
  grep -q 'SHORT NIGHT' brief.py
  python -c "import nw_runlog; assert hasattr(nw_runlog,'run_spans')"
  ```


### [x] T7 -- Document 0.6.0 and prove the suite is green
- model: deepseek
- depends-on: everything

Rewrite `README.md` for what 0.6.0 actually is. It must contain these literal strings, put
there deliberately rather than hoped for: `-Until`, `discord_regrade`, `openrouter`,
`aharg-nw`, `reactions.add`, `assumed`, `NW_MIN_RUN_FRACTION`. Cover: the anytime-start window and the by-hand
launch line, the local-first / OmniRoute per-call ladder with Gemini removed, the six-tier
queue with its overflow floor, the unconditional 08:00 report with tappable keycaps, the
09:00 precedence (reaction, then digit reply, then assume 1), and the five block kinds.

List the environment variables in one table: `NW_SLACK_TOKEN`, `NW_SLACK_CHANNEL`,
`NW_SLACK_DISABLE`, `NW_NTFY_TOPIC`, `NW_NTFY_DISABLE`, `OPENROUTER_KEY`, `NW_MIN_RUN_FRACTION`. `GEMINI_KEY` must
not appear anywhere.

Then run the full suite and the PowerShell parse gate, and fix anything that fails rather
than reporting it.

- **done-when:** `python -m pytest tests/ -q` and `pwsh tests/parse-ps1.ps1` both exit 0 and
  `README.md` carries all six literal strings.
- **verify:**
  ```bash
  python -m pytest tests/ -q
  pwsh tests/parse-ps1.ps1
  grep -q -- '-Until' README.md
  grep -q 'discord_regrade' README.md
  grep -q 'openrouter' README.md
  grep -q 'aharg-nw' README.md
  grep -q 'reactions.add' README.md
  grep -q 'assumed' README.md
  grep -q 'NW_MIN_RUN_FRACTION' README.md
  test -z "$(grep -ril gemini_key . )"
  ```

# NIGHT-WORKER 0.5.0 - Cut the cloud, heal itself, report once to Slack

status: ready
version: night-worker-0.5.0
repo: aharger3/night-worker
doc: Projects/night-worker.md

target: Make the 09:00 to 08:00 window run unattended for real - stage C reads frames on the local GPU instead of Google's quota, the worker restarts its own stages instead of dying silently, and the only thing that reaches Austin is one structured 08:00 message in Slack #night-worker that he can reply to in a thread.

## Why this version exists

The 2026-08-16 audit found the worker had drifted off its own design in one expensive way:
**stage C ships every 1080p keyframe to `gemini-flash-latest` in Google's cloud.** It is
throttled by `GEMINI_SLEEP = 6.0` to stay inside a free-tier request cap, so the night is
paced by someone else's quota, not by the 6 GB card. `qwen2.5vl:3b` - the local vision
model this box already has pulled, and the reason the card was the constraint in the first
place - is called from nowhere. Neither is OmniRoute.

Two nights in a row also ended in ways nobody found out about until the morning:

- **2026-08-15** the worker died at ~16:53 with the task still showing `Ready` and result 0.
  No crash log, no alert. On restart it re-walked all 213 ids through `caption_extract`
  from scratch before resuming, burning 30+ minutes.
- **2026-08-16** stage C spun **59,398 no-op passes** in five hours and grew
  `night-log.jsonl` to 209 MB. Already fixed on the box and pushed (`fcea8af`) - stage C
  now exits 3 when drained and the worker breaks - but the shape of the failure is the
  point: *nothing noticed.*

That is the actual answer to "why can't I trust it to run 23 hours." Not because the work
is hard - because every interruption so far has needed a human to spot it. This version
makes the worker recover from its own interruptions and report once, at the end.

## Settled in the 2026-08-16 grilling - never re-elicit

1. **Stage C is local-first with a cloud fallback.** `qwen2.5vl:3b` reads every frame. Only
   when its output fails to parse or comes back empty does that one frame retry on Gemini.
   The happy path touches no quota; a weak 3B never silently loses a frame.
2. **Slack `#night-worker` is the notification AND response surface.** Channel
   `C0BQK5RUXL2` in workspace `austin-rox7601`, posted through the existing one-app
   `vault_agents` bot with `username: Night Worker`. Threads are the conversation.
3. **One message, at 08:00. Not a heartbeat, not per-stage.** Structured: what finished,
   what failed and why, and a short numbered list of recommendations for what to work on
   next. He replies in the thread.
4. **The numbered recommendations stay.** "Drop the multiple choice" means drop the
   *buttons* - Slack has no reply-with-choice widget worth building. It does not mean drop
   the recommendation-first format. He can answer `2` or he can talk; both land in the same
   thread.
5. **ntfy survives, demoted.** Topic moves from `aharg-loop` to **`aharg-nw`**, and it
   carries machine-state alarms only - the worker is dead and self-heal already failed. No
   "all good" pings. Per `Projects/agents/agent-hosting.md`: Slack is for agents that ask
   Austin something, ntfy is for alarms nobody answers.
6. **Interruptions get fixed by the worker, not reported to Austin.** A stage that throws
   is retried in place; a stage that dies takes the worker's supervisor loop with it only
   after it has failed 3 times. Only the third failure is worth a human.
7. **This worker is a script, not an agent.** It does the same thing every night and needs
   no judgment, so it gets no adaptive loop, no Lindy-style planner, and no model deciding
   what to do next. The catalog is fixed. That was already the v0.3.0 decision and it holds.

## What must not change

- `think = false` on every Ollama call. `qwen2.5vl:3b` and `qwen3.5:4b` both return an
  empty `response` without it, which reads exactly like a broken prompt.
- `num_ctx = 16384` and `OLLAMA_MAX_LOADED_MODELS=1`. The card is 6 GB and is shared with
  an interactive user.
- **Every `.ps1` copied to the box must be ASCII-only.** Non-ASCII characters become parse
  errors there. No smart quotes, no arrows, no em dashes in PowerShell files.
- No model reports its own success. Every row is judged by the file it wrote.
- No new scheduled task, no cron. `\NightWorker` already exists.


### [x] T1 -- Stage C reads frames on the local GPU first, Gemini only on failure
- model: glm

`stagec.py` currently calls `gemini()` for every keyframe and paces itself with
`GEMINI_SLEEP = 6.0` to survive a free-tier cap. Invert it.

Add `ollama_vision(png)` to `stagec.py`: POST to `http://localhost:11434/api/generate` with
`model: "qwen2.5vl:3b"`, the PNG base64 in the `images` array, the **same prompt string the
Gemini call already uses**, and an options block carrying `num_ctx: 16384`. Send
`"think": false` at the top level - this is not optional, the model returns an empty
`response` without it. Parse the same JSON shape out of `response` that `gemini()` parses
out of its own reply; reuse the existing extraction helper rather than writing a second
JSON-from-prose parser.

Rewire the frame loop so each frame tries `ollama_vision` first. Fall through to the
existing `gemini()` **only** when the local read raises, returns empty, or fails to parse -
and record which one served the frame by writing `"model": "qwen2.5vl:3b"` or
`"model": GMODEL` into the frame's output row, so a night that quietly fell back to cloud
is visible in `corpus_frames.jsonl` instead of invisible. Sleep `GEMINI_SLEEP` only on the
fallback path; a local read must not sleep 6 seconds.

Add `--vision {local,gemini,auto}` defaulting to `auto` (the fallback behaviour above);
`local` disables the fallback entirely, `gemini` restores the old cloud-only path for
daytime spot-checks. When `GKEY` is unset, `auto` must degrade to `local` and keep going
instead of exiting 1 the way it does today - an unattended night must never die on a
missing cloud key.

Extend the existing dependency-injection seam (`deps` / `gemini_fn`, already used by
`tests/test_ladder.py`) with an `ollama_fn` so this path is testable with no GPU and no
network.

Write `tests/test_vision.py` covering, with fake runners only: local success never calls
the Gemini fn, an empty local response falls through to Gemini, an unparseable local
response falls through to Gemini, `--vision local` with a broken local read gives up on
that frame without calling Gemini, and the `model` field is written correctly in each case.

- **done-when:** `python -m pytest tests/test_vision.py -q` passes, no test opens a socket,
  and `grep` shows `qwen2.5vl:3b` and `"think"` both present in `stagec.py`.
- **verify:**
  ```bash
  python -m pytest tests/test_vision.py -q
  grep -q 'qwen2.5vl:3b' stagec.py
  grep -q '"think"' stagec.py
  grep -q 'ollama_fn' stagec.py
  ```


### [x] T2 -- slack.py: post one message to #night-worker as Night Worker
- model: deepseek

New `slack.py`, stdlib only (`urllib`, `json`, `os`), same shape and discipline as the
existing `notify.py` - it catches its own send failures and never raises into the caller.

`post(title, blocks, thread_ts=None) -> str|None` POSTs to
`https://slack.com/api/chat.postMessage` with `channel` from `NW_SLACK_CHANNEL`
(default `C0BQK5RUXL2`), `username: "Night Worker"`, `icon_emoji: ":crescent_moon:"`, and
the message text. It returns the `ts` of the posted message so a later call can thread onto
it, or `None` on any failure.

The bot token is read from `NW_SLACK_TOKEN`, falling back to a `.slack-token` file beside
the script - mirroring exactly how `GKEY` already resolves from `.gemini-key`. Add
`.slack-token` to `.gitignore` in the same row. Never log the token, never echo it in an
error message.

`NW_SLACK_DISABLE=1` makes `post` a no-op returning `None` without opening a socket, so dry
runs and CI never hit Slack. Add `--self-test` that renders and prints a full example
payload with `NW_SLACK_DISABLE` forced on, exits 0, and opens no socket.

- **done-when:** `python slack.py --self-test` prints a payload showing channel
  `C0BQK5RUXL2` and username `Night Worker`, exits 0, and makes no network call.
- **verify:**
  ```bash
  NW_SLACK_DISABLE=1 python slack.py --self-test
  grep -q 'C0BQK5RUXL2' slack.py
  grep -q '.slack-token' .gitignore
  ```


### [x] T3 -- brief.py: one structured 08:00 report, built from tonight's log only
- model: glm
- depends-on: T2

New `brief.py`. It reads `night-log.jsonl` and produces the single message Austin gets each
morning. It must be readable by a person half awake, so: what got done, what broke, and
what to do about it - in that order, nothing else.

**Only tonight's rows count.** Select rows whose `ts` falls in the window that ends at this
run's stop time and begins at the preceding `worker start` row (fall back to a 23-hour
lookback if no start row is found). This is the bug that makes `notify.py`'s conditions
wrong today - it reads the entire log, so counts accumulate across nights forever.

The message has three parts:

1. **Finished** - per stage, the counts of `ok` / `fail` / `skip`, plus corpus deltas:
   how many rows `corpus_entries.jsonl` and `corpus_frames.jsonl` grew by tonight, and how
   many frames were served locally vs. by the Gemini fallback (read the `model` field T1
   writes). A night that produced nothing must say so in the first line, not bury it.
2. **Broke** - the top 3 failure `detail` strings by count, each with its number. Truncate
   each to one line; the full text is in the log.
3. **Recommendations** - a **numbered** list, at most 4, cheapest-first, generated from
   fixed rules over the numbers above, not from a model. Ship at minimum these rules:
   most failures are `unavailable` -> recommend a `--retry-failed` pass once yt-dlp
   updates; stage C drained with extracts left unmatched -> recommend widening the
   timestamp match; Gemini fallback served more than 20% of frames -> recommend checking
   whether `qwen2.5vl:3b` is loading at all; nothing ran -> recommend checking the
   scheduled task and Ollama. End the list with a plain-English line telling him he can
   reply with a number or just talk in the thread.

`main()` posts it through `slack.post()` from T2 and **also** writes the same content as
markdown to the path given by `--out` (the worker passes the vault path). A Slack failure
must not stop the file being written, and neither failure may return non-zero - a broken
report must never mark a good night as failed.

**The written markdown must open with YAML frontmatter carrying `thread_ts:` (the `ts`
`slack.post()` returned), `channel:` and `date:`.** This is the whole read-back path: the
Slack thread is where Austin answers, and the only way a later Claude session or cloud
routine knows *which* thread to call `slack_read_thread` on is this line. If the post
failed, write `thread_ts: null` rather than omitting the key.

`--dry-run` prints the rendered message to stdout and posts nothing.

Write `tests/test_brief.py` against a synthetic two-night `night-log.jsonl` fixture,
asserting: only tonight's rows are counted, the counts are right, each recommendation rule
fires on the log it is meant to fire on and stays silent otherwise, and the recommendations
are numbered.

- **done-when:** `python -m pytest tests/test_brief.py -q` passes and
  `python brief.py --log <fixture> --dry-run` prints a three-part message with a numbered
  recommendation list, posting nothing.
- **verify:**
  ```bash
  python -m pytest tests/test_brief.py -q
  NW_SLACK_DISABLE=1 python brief.py --log tests/fixtures/two-night-log.jsonl --dry-run
  grep -q 'thread_ts' brief.py
  ```


### [x] T4 -- The worker survives its own interruptions instead of dying silently
- model: glm

This is the row that makes 23 hours trustworthy. Three changes in `worker.ps1`, all
ASCII-only.

**Wrap each stage call in a supervisor.** Add `Invoke-Stage -Name <string> -Body
<scriptblock> -MaxFailures 3`. It runs the body in `try/catch`; on a throw or a non-zero,
non-3 exit it logs a `stage-retry` row carrying the stage name, the attempt number and the
error text, waits 60 seconds, and runs it again. Only after 3 consecutive failures does it
log `stage-abandoned` and move on to the next stage - it must never take the whole night
down. Stage exit code 3 means drained and is a clean stop, not a failure.

**Add a resume checkpoint.** Write `checkpoint.json` beside the log after every stage
transition, holding the stage name and the last id completed. On start, if a checkpoint
exists whose timestamp is inside the current window, skip directly to that stage instead of
re-walking every earlier stage from scratch. This is the 30 minutes the 2026-08-15 restart
burned re-scanning 213 already-done ids.

**Call the brief exactly once, at the stop.** Replace the existing `notify.py` invocation
at the end of the run with `brief.py --log $LogJsonl --out $VaultLog`, still guarded so a
failure there can never gate the `stop` row. `notify.py` keeps running too but only for the
alarm case - see T5.

Extend `tests/parse-ps1.ps1` so it still passes as a real `pwsh` parser gate, and add
`tests/test_supervisor.ps1` that dot-sources the supervisor function and asserts, with
scriptblocks that fake their outcomes: a body that throws twice then succeeds runs 3 times
and reports success; a body that throws 3 times logs `stage-abandoned` and returns control;
a body returning exit code 3 is treated as clean and is not retried.

- **done-when:** both `pwsh tests/parse-ps1.ps1` and `pwsh tests/test_supervisor.ps1` exit
  0, and `worker.ps1` contains no non-ASCII byte.
- **verify:**
  ```bash
  pwsh tests/parse-ps1.ps1
  pwsh tests/test_supervisor.ps1
  ! LC_ALL=C grep -qP '[^\x00-\x7F]' worker.ps1
  ```


### T5 -- notify.py demoted to alarms on ntfy topic aharg-nw
- model: glm

`notify.py` currently owns three conditions and posts them to `aharg-loop` at the end of
every night. T3 takes over the reporting job, so notify keeps only the case where the
worker is in no state to report on itself.

Change `DEFAULT_TOPIC` to **`aharg-nw`**. Delete the "stage ran but produced nothing" and
"stage failing too often" conditions - both are now lines in the brief and do not belong on
an alarm channel. Keep exactly one condition: **the worker did not run tonight, or ran and
never reached its stop row.** Scope it to tonight's rows using the same window logic T3
defines - today it reads the whole log, which is why it can never fire again after one good
night.

Keep `NW_NTFY_TOPIC`, `NW_NTFY_DISABLE`, and `--self-test`. Update `--self-test` to print
the single remaining payload. Update the module docstring so it says what this file is for
now: machine-state alarms only, nothing to answer, silence means healthy.

Put the coverage for the surviving condition in `tests/test_notify.py` (create it if the
existing notify coverage lives elsewhere) and update it for the removed conditions rather
than deleting the coverage outright.

- **done-when:** `python notify.py --self-test` prints one payload naming topic `aharg-nw`,
  and the two removed conditions appear nowhere in the file.
- **verify:**
  ```bash
  NW_NTFY_DISABLE=1 python notify.py --self-test
  grep -q 'aharg-nw' notify.py
  ! grep -q 'aharg-loop' notify.py
  python -m pytest tests/test_notify.py -q
  ```


### T6 -- The vault markdown mirror actually gets written and committed
- model: glm

`worker.ps1` defines `$VaultLog = "C:\Users\aharg\Austin's Vault\Areas\Daily\night-log.md"`
and the file has never once appeared in the vault - the whole `Areas/Daily/` folder stops at
2026-07-27. The mirror is the only durable handoff out of the box, so this is a silent
single point of failure.

Add `Write-Mirror` to `worker.ps1`: render the current night's counts as markdown, create
the parent directory if missing, write `$VaultLog`, then `git -C` the vault to `add`,
`commit` (message `night-worker: mirror <date>`) and `push`. Every one of those steps runs
in `try/catch` and logs a `mirror` row with `ok` or `fail` and the error - a vault that is
mid-rebase must never stop the corpus work. If nothing changed, a no-op commit is a success,
not a failure.

Call it from the existing periodic point in the pass loop and once more immediately before
the stop row, so the last state of the night always lands.

The runner cannot see the box or the vault, so the test uses a throwaway git repo in a temp
directory: `tests/test_mirror.ps1` initialises one, points the mirror at it, runs
`Write-Mirror`, and asserts the file exists, is non-empty, and that `git log` in that repo
shows exactly one new commit.

- **done-when:** `pwsh tests/test_mirror.ps1` exits 0 and leaves a committed, non-empty
  markdown file in its temp repo.
- **verify:**
  ```bash
  pwsh tests/test_mirror.ps1
  pwsh tests/parse-ps1.ps1
  ```


### T7 -- Stop the 09:00 trigger reporting a false failure
- model: glm

`\NightWorker` has both a 09:00 daily trigger and an at-startup trigger, with
`MultipleInstances IgnoreNew`. When the box has not rebooted, the startup instance is still
running at 09:00, the daily trigger is refused, and `LastTaskResult` becomes
**`2147946720` (0x800710E0, "the operator or administrator has refused the request")**.
Nothing is actually wrong, but the one field anyone checks to see whether the worker is
healthy reads as a failure - so a real failure is indistinguishable from this.

Fix it in `register-tasks.ps1`: keep both triggers, but make the daily trigger's action a
thin guard that exits 0 immediately when an instance is already running, instead of letting
Task Scheduler refuse the start. Document the 0x800710E0 code in a comment beside it so the
next person reading a task history knows what it meant historically.

The script must stay idempotent - re-running it re-registers cleanly over an existing task,
which is how it gets deployed.

**`tests/parse-ps1.ps1` must be edited in this row too.** The previous attempt failed here:
the gate parses only `worker.ps1` and `supervisor.ps1`, printed "parses clean" for both and
still exited 1, and never looked at `register-tasks.ps1` at all. Rewrite it to glob **every
`.ps1` in the repository** (`Get-ChildItem -Recurse -Filter *.ps1`), parse each with the real
`[System.Management.Automation.Language.Parser]`, print one line per file, and `exit 1` only
when a file actually has parse errors - and `exit 0` otherwise. An exit code that does not
match the printed result is the bug being fixed.

Do not add, remove, or reschedule any other task. No cron, no new schedule.

- **done-when:** `pwsh tests/parse-ps1.ps1` still passes with `register-tasks.ps1` included
  in the parse set, and the file contains the guard plus the documented code.
- **verify:**
  ```bash
  pwsh tests/parse-ps1.ps1
  grep -q '0x800710E0' register-tasks.ps1
  ```


### T8 -- Delete the dead scratch scripts and document the run
- model: deepseek
- depends-on: everything

The 2026-08-15 debugging session left 26 one-shot probes in the repo root - `_omni2.ps1`
through `_omni5.ps1`, `_vl.ps1`, `_vl2.ps1`, `_vl3.ps1`, `_vtt.ps1`, `_vttall.ps1`,
`_f2.ps1`, `_f480.ps1`, `_frames.ps1`, `_full.ps1`, `_g.ps1`, `_g2.ps1`, `_spd.ps1`,
`_t.ps1`, `_t2.ps1`, `_q.ps1`, `_omni_vl.ps1` and the rest - plus loose `inspect_entries.py`,
`norm_report.py`, `patch_nightworker.py`, `stagec_report.py`, `staged.py`, `stagee.py`,
`sym_probe.py`. They make the folder read as a scratchpad and none of them is referenced by
`worker.ps1`, `stagec.py`, `brief.py`, `slack.py` or `notify.py`.

Delete every file matching `_*.ps1` in the repo root. For the loose `.py` probes, grep each
name across the surviving files first and delete only the ones nothing references - report
any you kept and why. Add `night-log*.jsonl` to `.gitignore` so a 209 MB spin log can never
be committed.

Then update `README.md` to describe what 0.5.0 actually is: three stages, local-first
vision with a cloud fallback, self-healing stage supervisor, one Slack report at 08:00,
ntfy for alarms only. Include the two by-hand commands and the environment variables
(`NW_SLACK_TOKEN`, `NW_SLACK_CHANNEL`, `NW_SLACK_DISABLE`, `NW_NTFY_TOPIC`,
`NW_NTFY_DISABLE`, `GEMINI_KEY`).

- **done-when:** no `_*.ps1` remains, the full test suite passes, and `README.md` names
  `qwen2.5vl:3b`, `#night-worker` and `aharg-nw`.
- **verify:**
  ```bash
  test -z "$(ls _*.ps1 2>/dev/null)"
  grep -q 'qwen2.5vl:3b' README.md
  grep -q 'aharg-nw' README.md
  grep -q 'night-log' .gitignore
  python -m pytest tests/ -q
  pwsh tests/parse-ps1.ps1
  ```

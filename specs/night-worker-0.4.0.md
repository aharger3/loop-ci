# NIGHT-WORKER 0.4.0 - unblock stage C throughput

status: ready
version: night-worker-0.4.0
repo: aharger3/night-worker
doc: Projects/night-worker.md

target: get the 213 waiting extracts through stage C unattended - kill the 403 wall, stop re-burning known-dead videos, and make the 09:00 worker actually run stage C instead of leaving it to a hand-typed command.

<!-- State on 2026-08-15, read from Desktop\ops\night\night-log.jsonl (1,612 lines, 3 runs):
     stage A yt_captions      214 ok / 6 fail    -> captions/ 215 files
     stage B caption_extract  213 ok / 6 fail    -> extracts/ 213 files, 1,263 corpus_entries rows
     stage C stagec.py         33 ok / 35 x 403  -> corpus_frames.jsonl 174 rows

     Two findings that this version exists to fix:
       1. 51% of stage C video downloads return HTTP 403 Forbidden. Captions are unaffected -
          only the 1080p video pull is blocked. Single hardcoded client `android_vr`, format 137.
       2. worker.ps1 NEVER INVOKES stagec.py. grep for "stagec" in worker.ps1 returns nothing.
          Stage C has only ever run when Austin typed the command. That is why 213 extracts sit
          unprocessed while the box is idle at 3am.

     The earlier BOM crash (213 rows, "Unexpected UTF-8 BOM") was already fixed by hand at
     15:01 - stagec.py reads utf-8-sig everywhere now. Do not re-fix it.

     Settled by grilling 2026-08-15: loop-ci edits the code and the box pulls it; blockers go to
     ntfy topic aharg-loop, NOT Remote Control (pairing unconfirmed); no cookies-from-browser -
     the accepted risk stays IP rate-limiting, never account flagging. The 08:00 Haiku brief and
     catalog.jsonl generalization are explicitly OUT of this version. -->


### T1 -- Client + format ladder so a 403 is not the end of the video

- model: glm

`download()` in `stagec.py` makes exactly one attempt, with the client and format both
hardcoded:

```python
cmd = [YTDLP, "--no-warnings", "--extractor-args",
       "youtube:player_client=android_vr", "-f", "137", "-N", "4",
       "-o", str(dest), f"https://www.youtube.com/watch?v={vid}"]
```

When that combination 403s, the video is abandoned. Replace it with an ordered ladder that
walks client/format pairs until one produces a file:

```python
LADDER = [
    ("android_vr",  "137"),
    ("web_safari",  "137"),
    ("tv",          "bestvideo[height<=1080][ext=mp4]"),
    ("ios",         "bestvideo[height<=1080][ext=mp4]"),
    ("web",         "bestvideo[height<=1080]"),
]
```

Rules the ladder must follow:

- Stop at the first rung that leaves a non-empty file at `dest`. Do not keep going.
- Sleep 5 seconds between rungs, and 30 seconds between videos, so a run reads as a slow
  human rather than a scraper. No cookies, no `--cookies-from-browser`, ever - Austin
  explicitly ruled out anything that ties this to his YouTube login.
- A rung whose stderr contains neither `403` nor `Forbidden` is a real error, not a block:
  return immediately with that stderr instead of walking the rest of the ladder. Burning
  four more attempts on "video unavailable" wastes twenty minutes per dead video.
- Return `(True, client)` on success and `(False, last_stderr)` on exhaustion, and have the
  caller log the winning client so the next session can see which rung is carrying the load.
  The success log line must be exactly this shape, because the report greps for it:

  `stagec ok <vid> <n> frames, <n> setups, client=<client>`

To make any of this testable on a runner with no network, `download()` must take an
injectable command runner: `def download(vid, dest, runner=subprocess.run, sleep=time.sleep)`.
Do not change its behaviour when called with the defaults.

Same pass, because it is the other thing blocking offline tests: every hardcoded
`C:\Users\aharg\...` path at the top of `stagec.py` (`ROOT`, `OUT`, `YTDLP`, `FFMPEG`) reads
from an env var with the current Windows value as its default - `NW_ROOT`, `NW_OUT`,
`NW_YTDLP`, `NW_FFMPEG`. The box behaves identically; the runner can point them at a tmpdir.

Write `tests/test_ladder.py` (stdlib `unittest`, no network, no pytest) covering: a fake
runner that 403s on rungs 1-2 and succeeds on rung 3 returns `(True, "tv")` and made exactly
three calls; a runner that 403s on every rung returns `False` after five calls; a runner
whose stderr says `Video unavailable` returns `False` after exactly one call.

- **done-when:** `download()` walks the five-rung ladder, bails early on a non-403 error, returns the winning client name, takes an injectable runner, and `tests/test_ladder.py` passes with no network access.
- **verify:**
  ```bash
  python3 -m py_compile stagec.py
  python3 -m unittest discover -s tests -p 'test_ladder.py' -v
  python3 -c "import re,sys; s=open('stagec.py',encoding='utf-8').read(); sys.exit(0 if all(c in s for c in ['web_safari','android_vr','\"tv\"','ios']) else 1)"
  python3 -c "import sys; s=open('stagec.py',encoding='utf-8').read(); sys.exit(1 if 'cookies-from-browser' in s else 0)"
  python3 -c "import inspect,sys,os; os.environ.setdefault('NW_ROOT','.'); import stagec; sys.exit(0 if 'runner' in inspect.signature(stagec.download).parameters else 1)"
  ```


### T2 -- Stop re-burning the videos that already failed five ways

- model: deepseek
- depends-on: T1

Stage C resumes by reading `corpus_frames.jsonl` and skipping any video that already has a
row. A video that fails has no row, so **every future run retries it from scratch.** With 35
videos 403ing on all five rungs, that is 35 x 5 attempts x ~30s of pure waste at the front of
every single night before any new work starts.

Add a failure ledger at `<NW_ROOT>/stagec_state.jsonl`, one JSON object per attempt:

```json
{"video_id": "abc123", "ts": "2026-08-16T02:14:03", "reason": "403", "attempts": 3}
```

- Before attempting a video, read the ledger. If its `attempts` is `>= 3`, skip it and log
  `stagec skip <vid> exhausted after 3 attempts`. Cheap skips go first, before the download.
- After a failed download, upsert the video's row with `attempts + 1` and the short reason
  (`403`, `unavailable`, `timeout`, `other`).
- On success, drop the video's row from the ledger entirely - a video that later works must
  not stay marked.
- Add a `--retry-failed` flag that ignores the `>= 3` cutoff for one run, for when the ladder
  gets a new rung and the dead pile deserves another go.
- Add `--limit N` to cap videos processed in one invocation. T4 needs it to keep a single
  stage-C pass inside the night window.

Write `tests/test_ledger.py` (stdlib `unittest`, tmpdir, no network) covering: a video with
`attempts: 3` is skipped without the runner ever being called; a failure on a fresh video
writes `attempts: 1`; a second failure upserts to `2` rather than appending a duplicate row;
a success removes the row; `--retry-failed` processes an exhausted video anyway.

- **done-when:** `stagec_state.jsonl` bounds retries at 3 attempts per video, upserts instead of appending duplicates, clears a row on success, `--retry-failed` and `--limit N` both work, and `tests/test_ledger.py` passes.
- **verify:**
  ```bash
  python3 -m py_compile stagec.py
  python3 -m unittest discover -s tests -p 'test_ledger.py' -v
  python3 -c "import sys; s=open('stagec.py',encoding='utf-8').read(); sys.exit(0 if all(k in s for k in ['stagec_state.jsonl','--retry-failed','--limit']) else 1)"
  ```


### T3 -- One way for the night to say it is stuck

- model: deepseek

Settled this round: blockers go to **ntfy topic `aharg-loop`**, the same topic loop-ci already
pushes to and that is already on Austin's phone. Not Remote Control - pairing is unconfirmed
and the 08:00 brief is deliberately out of this version.

Create `notify.py`. One function, `notify(title, lines, priority="default")`, POSTing to
`https://ntfy.sh/aharg-loop` with stdlib `urllib.request` only - no `requests`, the repo stays
dependency-free.

It fires on exactly three conditions, and nothing else. A noisy channel gets muted, and a muted
channel is the same as no channel:

| condition | title |
|---|---|
| a stage's failure rate is over 30% across at least 10 attempts | `night-worker: <stage> failing` |
| a stage ran and produced zero new output rows | `night-worker: <stage> produced nothing` |
| the worker wrote no start line for a night at all | `night-worker: did not run` |

Every notification body names the count, the top failure reason, and the file to look at. A
notification that says only "stage C is failing" costs a phone unlock and answers nothing.

`NW_NTFY_TOPIC` overrides the topic; `NW_NTFY_DISABLE=1` turns it into a no-op that still
returns cleanly, so a test run never wakes anyone.

Add `--self-test`, which builds and prints the exact payload for all three conditions and
exits 0 **without opening a socket**. That is what the runner checks.

- **done-when:** `notify.py --self-test` prints three payloads and exits 0 with no network call, the topic and disable switch are both env-overridable, and only the three listed conditions can fire.
- **verify:**
  ```bash
  python3 -m py_compile notify.py
  NW_NTFY_DISABLE=1 python3 notify.py --self-test
  python3 -c "import sys; s=open('notify.py',encoding='utf-8').read(); sys.exit(0 if 'aharg-loop' in s and 'urllib' in s else 1)"
  python3 -c "import sys; s=open('notify.py',encoding='utf-8').read(); sys.exit(1 if 'import requests' in s else 0)"
  ```


### T4 -- Make the 09:00 worker actually run stage C

- model: glm
- depends-on: T3

This is the row that matters most and it is not a bug fix - it is a missing call.
`grep -c stagec worker.ps1` returns **0**. Stages A and B run unattended every night; stage C
has only ever run because Austin typed it. That is the entire reason 213 extracts are sitting
in `extracts/` while the box does nothing at 3am.

Add a stage C block to `worker.ps1`, after stage B, inside the existing night loop:

- Call `python stagec.py --limit 25` per pass, then loop back to the top. Chunking matters:
  one unbounded stage-C call would blow past 08:00 and get killed mid-video, and the partial
  `.mp4` in `_stagec/` would be left behind.
- Respect the two guards that already exist and are already correct - re-use them, do not
  write new ones. `Test-BoxFree` gates every pass (Austin at the keyboard, or another process
  holding VRAM, means sleep 5 minutes and re-check), and the 08:00 `$stop` check aborts before
  starting a pass that cannot finish.
- Log `worker stagec-pass <n> <exitcode>` per pass into `night-log.jsonl`, so a stage C that
  silently stops is visible in the morning as an absence of passes.
- At the end of the night, before the existing `worker stop` line, call `notify.py` with the
  night's tallies so the three T3 conditions get evaluated exactly once per night.
- Stage C needs no GPU - Gemini reads the frames and ffmpeg only seeks. But it does need the
  network and it does write to disk, so it stays inside `Test-BoxFree` anyway.

Because the runner is `ubuntu-latest` and cannot execute the worker for real, add
`tests/parse-ps1.ps1`: it parses `worker.ps1` with
`[System.Management.Automation.Language.Parser]::ParseFile`, prints any syntax errors, and
exits non-zero if there are any. `pwsh` is present on the runner, so this is a genuine syntax
gate rather than a grep.

- **done-when:** `worker.ps1` calls `stagec.py --limit 25` in a loop inside the night window, gated by the existing `Test-BoxFree` and 08:00 stop, logs one line per pass, calls `notify.py` once at the end, and parses clean.
- **verify:**
  ```bash
  pwsh -NoProfile -File tests/parse-ps1.ps1
  pwsh -NoProfile -Command "if ((Select-String -Path worker.ps1 -Pattern 'stagec' -SimpleMatch).Count -lt 1) { exit 1 }"
  pwsh -NoProfile -Command "if ((Select-String -Path worker.ps1 -Pattern 'Test-BoxFree' -SimpleMatch).Count -lt 2) { exit 1 }"
  pwsh -NoProfile -Command "if ((Select-String -Path worker.ps1 -Pattern 'notify.py' -SimpleMatch).Count -lt 1) { exit 1 }"
  ```


### T5 -- Repo hygiene, so the first push does not leak a key or 300 MB

- model: deepseek

`Desktop\ops\night\` becomes `aharger3/night-worker`, and it currently holds a live API key and
about 350 MB of scratch. Write `.gitignore` first, before anything else in this row.

Must be ignored, and the key is not negotiable - `.gemini-key` is a real Google API key sitting
in the repo root:

```
.gemini-key
night-log.jsonl
worker.lock
_stagec/
_frames/
_frames2/
_full/
_pb/
_probe/
_probe2/
_spd/
_vtt/
captions/
captions_ts/
extracts/
*.mp4
*.mp4.part
*.png
__pycache__/
```

Then `README.md`, and keep it to one screen: what the three stages are, the one command to run
the worker by hand, the one command to run stage C by hand, where the log goes
(`night-log.jsonl` local, `Areas/Daily/night-log.md` in the vault), and a line saying the
Gemini key lives in `.gemini-key` and is never committed.

Do not add `requirements.txt`. Both scripts are stdlib-only and an empty requirements file just
gives the loop-ci runner something to fail on.

- **done-when:** `.gitignore` exists and covers `.gemini-key`, the scratch directories and the media files; `README.md` documents the three stages and both by-hand commands; no `requirements.txt` was added.
- **verify:**
  ```bash
  test -f .gitignore
  test -f README.md
  test ! -f requirements.txt
  python3 -c "import sys; s=open('.gitignore',encoding='utf-8').read().split(); sys.exit(0 if all(p in s for p in ['.gemini-key','_stagec/','captions_ts/','*.mp4']) else 1)"
  python3 -c "import sys; s=open('README.md',encoding='utf-8').read(); sys.exit(0 if len(s) > 400 and 'stagec' in s else 1)"
  ```

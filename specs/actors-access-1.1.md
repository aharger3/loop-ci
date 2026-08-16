# ACTORS ACCESS 1.1 - Make the bot actually submit

status: ready
version: actors-access-1.1
repo: aharger3/Actors-Access-Automation
doc: Projects/actors-access-bot.md

target: Fix the date window that has silently dropped every breakdown since June, give CI a memory so the fix cannot cause duplicate submissions, and replace the failure-only Telegram alert with ntfy that shouts when a run submits zero.

## Why this version exists

The bot runs every morning at 13:00 UTC and GitHub reports success. Verified
2026-08-15 across runs 31887205420, 31808478503, 31606046106, 31316625575:

```
   Submitted : 0
   Skipped   : 0
   Errors    : 0
```

Every region, every day, for at least a week. Three defects, all confirmed by
reading the code and the run logs:

1. **`parseBreakdownDate` throws away the time of day.** `src/breakdowns.js`
   matches only `(\d{2}\/\d{2}\/\d{2})` out of a cell that actually reads
   `08/14/263:16 PM`, then builds `new Date("2026-08-14T00:00:00")` — local
   midnight. `isRecent` compares that midnight against `Date.now()`. At the
   09:26 ET run, a breakdown posted 3:16 PM *yesterday* — 18 real hours old —
   measures as 33 hours old and is skipped. Everything posted after ~9am the
   previous day is dropped. That is nearly the entire posting day.

2. **CI has no memory.** `.gitignore` lists `submissions_log.json`, so the
   runner checks out a repo without it, `readLog()` returns `[]`, and
   `isAlreadySubmitted` can never fire. The artifact upload step confirms it:
   `No files were found with the provided path: submissions_log.json`. Fix
   defect 1 alone and the bot re-submits the same roles to the same casting
   directors every single morning.

3. **Zero-submit runs are indistinguishable from working runs.** The workflow
   only curls Telegram `if: failure()`, and `index.js` exits 0 whenever
   `totalErrors === 0`. A bot that finds nothing forever is a green check.

**Settled by Austin, 2026-08-15 — do not re-decide these:**

- 1.1 repairs the existing auto-submit bot. No rescope to email-parse.
- Dedup state is **committed back to the repo**, not cached.
- **No submission cap**, and the region list stays exactly as `DAILY_REGIONS`
  has it today — all 14.
- Alerting goes to **ntfy topic `aharg-errors`** (`https://ntfy.sh/aharg-errors`,
  public topic, no secret needed). Telegram is removed.
- **Forward-only.** No catchup run over the ~2 months of skipped breakdowns.
- "New" means **since the last successful run**, read from committed state,
  with a 48-hour floor when no state exists.
- Proof of submission is a **dry-run mode plus one live single-role dispatch**
  that Austin eyeballs in his Actors Access submission history.

**Contract shared by more than one row — `run-summary.json`**, written to the
repo root by `src/index.js` at the end of every run, success or failure:

```json
{
  "mode": "daily",
  "dryRun": false,
  "startedAt": "2026-08-16T13:00:04.000Z",
  "finishedAt": "2026-08-16T13:07:11.000Z",
  "submitted": 3,
  "skipped": 11,
  "errors": 0,
  "roles": [{ "breakdownTitle": "THE SEED", "roleName": "TONY", "region": "Southeast (AL, FL, GA, KY, LA, MS, NC, SC, TN, VA)", "status": "submitted" }]
}
```

Both T3 and T4 depend on that exact shape. Neither may change it.

**Run 1 (31916106338), 2026-08-15 — T1/T2/T3 landed; T4/T5 lost to the tier, not
the spec.** Both burned all three attempts in 5–11 seconds with no stdout and no
file edits — an empty completion, not failed work. T2 passed on deepseek at
23:59, then every later deepseek row returned empty; night-worker-0.4.0 hit the
identical pattern twenty minutes later and was moved to glm for the same reason.
T4/T5/T6 are pinned to glm here. Note that `run-spec.ps1` redirects agent stderr
to a temp file and never prints it, so this class of failure leaves an empty log
group and is invisible from the run page.


### [x] T1 -- Parse the real posting time and window against the last successful run
- model: opus

`src/breakdowns.js` is where the bot goes blind. Rewrite the date handling.

`parseBreakdownDate(raw)` must parse the **full** cell, not just the date. The
live format has no separator between the year and the hour — `08/14/263:16 PM`,
`08/13/2611:02 AM`, `04/09/265:33 PM`. Match `MM/DD/YY` followed immediately by
`H:MM AM/PM` and return a real `Date`. Actors Access publishes these times in
**US Eastern**; the GitHub runner is UTC, so build the Date in Eastern and
convert, do not use bare `new Date(string)`. Return `null` only when the cell
genuinely has no parseable timestamp.

Replace `isRecent(dateRaw)` with `isNewSince(dateRaw, sinceMs)`: true when the
parsed time is at or after `sinceMs`. A cell that fails to parse must still
return `true` — being conservative here means an extra detail-page visit, and
dedup catches the duplicate; the reverse silently loses roles, which is the bug
this row exists to kill.

The watermark comes from a new `src/state.js` reading and writing `state.json`
at the repo root: `{ "lastSuccessfulRunAt": "<ISO>" }`. `scrapeRegion` takes
`sinceMs` from the caller. When `state.json` is missing or has no timestamp,
`sinceMs` is **now minus 48 hours**. `src/index.js` writes
`lastSuccessfulRunAt` **only** when the run finishes with `totalErrors === 0`,
and never in dry-run mode. Onboard mode ignores the watermark entirely, as
today.

Export the pure helpers — `parseBreakdownDate`, `isNewSince` — from
`src/breakdowns.js` alongside `scrapeRegion` so they can be tested without a
browser.

Write `test/window.test.js` using node's built-in `node:test` and `node:assert`.
No new npm dependencies, and it must not require `playwright` transitively.
Cover at minimum:
- `08/14/263:16 PM` parses to 2026-08-14 15:16 Eastern, not midnight.
- `08/13/2611:02 AM` parses to 11:02, not 1:02.
- A breakdown posted 18 real hours ago is new when the watermark is 24h back
  (the exact case the live bot got wrong).
- A breakdown posted 3 days ago is not new against a 48h floor.
- An unparseable cell returns `true` from `isNewSince`.

- **done-when:** `parseBreakdownDate` returns the correct hour and minute for the run-time formats above, `isNewSince` windows against a caller-supplied watermark backed by `state.json` with a 48h fallback, and `node --test test/window.test.js` passes with no npm install.
- **verify:**
  ```bash
  node --test test/window.test.js
  test -f src/state.js
  grep -q "isNewSince" src/breakdowns.js
  grep -q "lastSuccessfulRunAt" src/state.js
  grep -q "module.exports" src/breakdowns.js && node -e "const b=require('./src/breakdowns');if(typeof b.parseBreakdownDate!=='function'||typeof b.isNewSince!=='function')process.exit(1)"
  ```


### [x] T2 -- Give CI a memory: commit the dedup log and the watermark back to the repo

Right now `.gitignore` hides `submissions_log.json`, so every CI run starts
amnesiac and `isAlreadySubmitted` is dead code.

Remove `submissions_log.json` from `.gitignore`. **Leave `.env` and
`sessions/cookies.json` ignored** — those are credentials and must never enter
the repo. Add a repo-root `submissions_log.json` containing `[]` and a repo-root
`state.json` containing `{}` if they do not already exist, so the first run has
something to read.

In `.github/workflows/daily-submit.yml`, both jobs need `permissions: contents:
write` and a commit-back step that runs `if: always()` after the bot, before the
artifact upload:

```yaml
      - name: Commit run state
        if: always()
        run: |
          git config user.name  "actors-access-bot"
          git config user.email "bot@users.noreply.github.com"
          git add submissions_log.json state.json run-summary.json || true
          git diff --staged --quiet || git commit -m "bot: run state $(date -u +%FT%TZ)"
          git pull --rebase --autostash || true
          git push
```

`git diff --staged --quiet ||` is load-bearing: a run with nothing new must not
fail the job on an empty commit.

- **done-when:** `submissions_log.json` is tracked in git, `.env` and `sessions/cookies.json` are still ignored, and both workflow jobs have `contents: write` plus a commit-back step guarded against empty commits.
- **verify:**
  ```bash
  grep -q "^submissions_log.json" .gitignore && exit 1 || true
  grep -q "^.env" .gitignore
  grep -q "cookies.json" .gitignore
  test -f submissions_log.json
  test -f state.json
  grep -q "contents: write" .github/workflows/daily-submit.yml
  grep -q "git diff --staged --quiet" .github/workflows/daily-submit.yml
  test "$(grep -c 'Commit run state' .github/workflows/daily-submit.yml)" -ge 2
  ```


### [x] T3 -- Add --dry-run and --limit, and write run-summary.json every run
- model: glm

`submit.js` has not executed a single submission since the June rewrite, because
no role ever survived the date filter. 1.1 must be provable without gambling a
real submission, and then provable with exactly one.

Extract the decision logic out of the browser path into a new pure module
`src/plan.js`, so it can be tested with no Playwright and no credentials.
Export `planRoles({ roles, history, limit })` returning
`{ toSubmit, skipped }`: drops any role where `isAlreadySubmitted(history, ...)`
is true, then truncates to `limit` (`Infinity` when unset). `src/index.js` calls
it instead of doing the skip check inline.

Add two CLI flags to `src/index.js`:
- `--dry-run` — full login and scrape, but `submitRole` is **never called**.
  Each planned role logs `[dry-run] WOULD SUBMIT: "<role>" (<breakdown>)` and
  counts toward `submitted` in the summary. Nothing is appended to
  `submissions_log.json` and `state.json` is not advanced.
- `--limit N` — hard stop after N planned roles. This is what makes the live
  single-role proof safe.

Write `run-summary.json` to the repo root at the end of `main()`, on every path
including the fatal-error catch, matching the shape in "Why this version exists"
above exactly. `roles[]` carries one entry per attempted role with its final
status.

Add the flags to the workflow as `workflow_dispatch` inputs: a `mode` choice
gaining a `dryrun` option alongside the existing `daily`/`catchup`, and a
string input `limit` defaulting to empty. The daily scheduled run passes
neither.

Write `test/plan.test.js` with `node:test`, no new dependencies, covering: an
already-submitted role is dropped, a fresh role survives, `limit: 1` returns
exactly one role from a list of three, and `limit` unset returns all.

- **done-when:** `src/plan.js` exists and is unit-tested, `--dry-run` never reaches `submitRole` and never writes to the log or state, `--limit N` caps planned roles, and `run-summary.json` is written on every exit path in the documented shape.
- **verify:**
  ```bash
  node --test test/plan.test.js
  test -f src/plan.js
  node -e "const p=require('./src/plan');const h=[{breakdownTitle:'A',roleName:'r1'}];const r=[{breakdownTitle:'A',roleName:'r1'},{breakdownTitle:'B',roleName:'r2'},{breakdownTitle:'C',roleName:'r3'}];const o=p.planRoles({roles:r,history:h,limit:1});if(o.toSubmit.length!==1||o.toSubmit[0].breakdownTitle==='A')process.exit(1)"
  grep -q "dry-run" src/index.js
  grep -q "limit" src/index.js
  grep -q "run-summary.json" src/index.js
  grep -q "dryrun" .github/workflows/daily-submit.yml
  ```


### T4 -- Replace failure-only Telegram with ntfy that shouts on a zero-submit run
- model: glm

The reason a week of empty runs went unnoticed is that the only notification in
`.github/workflows/daily-submit.yml` is `if: failure()` curling Telegram.
Remove every Telegram step and both `TELEGRAM_*` references. Replace with ntfy
against the public topic `aharg-errors` — `https://ntfy.sh/aharg-errors`, no
token, no secret.

Add a notify step with `if: always()` at the end of both jobs. It reads
`run-summary.json` (written by `src/index.js`; the exact shape is documented
under "Why this version exists" in this spec — read it there, do not guess) and
sends one of three messages:

| condition | title | priority |
|---|---|---|
| job failed, or `run-summary.json` missing | `AA bot FAILED` + run URL | `urgent` |
| `submitted == 0` | `AA bot submitted 0 roles` + skipped/errors counts + run URL | `high` |
| `submitted > 0` | `AA bot submitted N` + the role names | `default` |

Use `curl -sS --retry 3 -H "Title: ..." -H "Priority: ..." -d "<body>" https://ntfy.sh/aharg-errors`.
Parse the JSON with `node -e`, not `jq` — node is already set up in the job and
`jq`'s presence is one less thing to depend on. A missing or malformed
`run-summary.json` must fall through to the failure message, never to silence.

The zero-submit alert is the whole point of this row: silence must mean the bot
worked, and today it means nothing at all.

- **done-when:** no Telegram reference survives in the workflow, both jobs notify ntfy topic aharg-errors on `if: always()`, and a run with `submitted: 0` produces a high-priority alert rather than a silent green check.
- **verify:**
  ```bash
  grep -ci telegram .github/workflows/daily-submit.yml | grep -q '^0$'
  grep -q "ntfy.sh/aharg-errors" .github/workflows/daily-submit.yml
  test "$(grep -c 'ntfy.sh/aharg-errors' .github/workflows/daily-submit.yml)" -ge 2
  grep -q "run-summary.json" .github/workflows/daily-submit.yml
  grep -q "submitted 0" .github/workflows/daily-submit.yml
  ```


### [x] T5 -- Rewrite the docs to say what 1.1 changed and why the green week was false
- model: glm

`README.md` still describes the May bot and `actors-access-progress.md` still
reads as if the thing works. `outage-postmortem.md` documents the June outage
that at least failed loudly; this one was worse and needs the same treatment.

Append a section to `outage-postmortem.md` titled exactly
`## Silent Zero — June 25 to August 15, 2026` covering: the midnight-truncation
bug in `parseBreakdownDate` with the before/after code, the gitignored
`submissions_log.json` that made CI amnesiac, and the failure-only alert that
let both hide behind a green check. Name the four verified run IDs
(31887205420, 31808478503, 31606046106, 31316625575). State the lesson in one
line: **exit code 0 is not evidence of work; a run must report what it did.**

Update `README.md` to document `--dry-run`, `--limit N`, the `dryrun`
workflow_dispatch mode, `state.json`, the committed `submissions_log.json`, and
ntfy alerting in place of Telegram. Bump `package.json` version to `1.1.0`.

- **done-when:** `outage-postmortem.md` carries the Silent Zero section naming all four run IDs, `README.md` documents the new flags and ntfy, and `package.json` reads 1.1.0.
- **verify:**
  ```bash
  grep -q "Silent Zero" outage-postmortem.md
  grep -q "31887205420" outage-postmortem.md
  grep -q "parseBreakdownDate" outage-postmortem.md
  grep -q "dry-run" README.md
  grep -q "ntfy" README.md
  grep -q "state.json" README.md
  node -e "if(require('./package.json').version!=='1.1.0')process.exit(1)"
  ```


### T6 -- Write the one-page checklist for Austin's live single-role proof
- model: glm
- depends-on: everything

Nothing in this spec can prove that `submitRole` still works against the live
site — that needs one real submission against Austin's real account, which no
unattended run may decide to make. This row leaves him a checklist and nothing
else.

Write `RUN-1.1-CHECKLIST.md` at the repo root. It must contain, in order, and
copy-pasteable:

1. **One-time local merge.** His machine holds ~856KB of submission history in
   an untracked `submissions_log.json` at
   `C:\Users\aharg\Desktop\Projects\actors-access-bot\`. Until it is pushed,
   the repo's dedup history is empty and the first real run may re-submit roles
   he already sent. Give the exact commands: pull the 1.1 branch, copy that file
   over the repo's `[]` placeholder, `git add submissions_log.json`, commit,
   push.
2. **Dry run.** `gh workflow run daily-submit.yml -f mode=dryrun` — then read
   the ntfy alert and the run log. State plainly what a healthy result looks
   like: `[dry-run] WOULD SUBMIT` lines naming breakdowns posted in the last two
   days. Zero lines means the window fix did not take and he should stop here.
3. **Live single submission.** `gh workflow run daily-submit.yml -f mode=daily -f limit=1`
   — exactly one role. Name where to verify it: his Actors Access submission
   history at `resumes.actorsaccess.com/austinharger`, and `run-summary.json` in
   the repo for which role to look for.
4. **Hand back to the schedule.** Nothing to do; the 13:00 UTC cron picks up
   from `state.json` the next morning.

Keep it under one page. Every command in its own fenced `bash` block.

- **done-when:** `RUN-1.1-CHECKLIST.md` exists with all four steps, the dry-run and limit-1 dispatch commands are copy-pasteable, and step 1 gives the exact local path of the untracked submissions log Austin must push before the first real run.
- **verify:**
  ```bash
  test -s RUN-1.1-CHECKLIST.md
  grep -q "mode=dryrun" RUN-1.1-CHECKLIST.md
  grep -q "limit=1" RUN-1.1-CHECKLIST.md
  grep -q "submissions_log.json" RUN-1.1-CHECKLIST.md
  grep -q "actorsaccess.com/austinharger" RUN-1.1-CHECKLIST.md
  test "$(grep -c '```bash' RUN-1.1-CHECKLIST.md)" -ge 3
  ```

# loop-ci

The Loop, as a GitHub Action. **Push a spec into `specs/` and it runs.** That is the whole
dispatcher — no session, no PC, no watchdog, no queue file.

## How it works

```
push specs/*.md
  -> plan     parse every spec (0 tokens). One bad spec fails here and costs nothing.
  -> run      one parallel job per spec, up to 20 at once. Tasks run in depends-on order.
  -> report   rendered table on the run page + a PR per spec on the target repo.
```

**A push runs the spec(s) the push touched, and nothing else.** A manual run from the Actions
tab must name its spec: leaving the box blank runs nothing and says so. It used to glob every
spec still marked `ready`, so one stale spec with an unfinished row rode along on every manual
run — which is how old versions ended up running in parallel with the one Austin meant.

Finished and abandoned specs live in `specs/archive/`, where neither the trigger nor the planner
can see them. `specs/` holds live work only.

Before the first token is spent, the run re-reads its spec from the current `main`. If the rows
were already checked off — by another run, or by hand — it stops there and reports a no-op
instead of doing the work twice.

## Spec format

Unchanged from the old loop, minus the FOCUS.md indirection — a spec is now self-describing:

```markdown
status: ready
version: omen-v3.2
repo: aharger3/tradingbot
doc: Projects/OMEN.md    (the vault note this run writes its summary into, and prunes)

target: one sentence on what this version is for.

### T1 -- do the thing
- model: opus
- depends-on: T0        (optional; `everything` means "runs last")

Prose describing the work.

- **done-when:** the test that proves it, in English, for the model.
- **verify:** `the same test as a shell command, for the runner`
```

Both are mandatory and they are not the same field. `done-when:` is prose the model
reads. **`verify:` is a shell command the runner executes, and its exit code is the
only thing that decides whether the row counts as done** — the model's own claim is
never read. A row with no `verify:` is refused before anything runs.

Two dialects, both legal:

```markdown
- **verify:** `python research/regression_gate.py`

- **verify:**
  ```bash
  python -c "import omen_bot,sys; sys.exit(0 if 'FLAG' in {m.name for m in omen_bot.SignalType} else 1)"
  python research/regression_gate.py
  ```
```

Three attempts per row. Attempt 2 and 3 are handed the verify command's real stderr,
so a retry is a bug-fix pass, not a re-roll.

## Models

One binary, three env blocks. DeepSeek and Z.ai both publish Anthropic-compatible endpoints
built for Claude Code, so there is no gateway and no translation layer.

| `model:` tag | goes to | when |
|---|---|---|
| `opus`, `fable`, `claude` | `claude-opus-5` @ api.anthropic.com | judgment rows only |
| `glm`, `z-ai/glm-5.2` | `z-ai/glm-5.2` @ OpenRouter, StreamLake pinned | bulk work needing judgment |
| anything else, blank | `deepseek/deepseek-v4-flash` @ OpenRouter, StreamLake pinned | the default. Grunt work, ~10x cheaper than glm |

Both gateway tiers pin their upstream provider with `CLAUDE_CODE_EXTRA_BODY`. Unpinned,
OpenRouter's weighted routing picks for you: measured 2026-08-09, deepseek-v4-flash is
$0.068/$0.137 per M on StreamLake and $0.140/$0.280 on thirteen other endpoints — the pin
is worth 2x on the same model.

**A row is never silently downgraded.** If its tier has no key, the row is *blocked* and you
get one notification with the exact command to fix it. Downgrading a judgment row onto a
cheap model is how a spec quietly produces confident garbage.

## Notifications

Three, ever, on topic `aharg-loop`:

| type | when |
|---|---|
| **start** | run began, with an ETA |
| **blocked** | the loop cannot continue without Austin — a key, a decision, or a run that confirmed nothing |
| **done** | finished, with a done/total count and every row's own plain-language line |

`ci/notify.sh` rejects any type outside those three, so a fourth cannot be added by accident.
A failed row inside an otherwise good run is *listed* in `done`, never paged — `blocked` is the
only type allowed to wake anyone.

**Where the buttons go.** The notification is a teaser; the report is a note in the Obsidian
vault, written by `ci/vault-sync.ps1`:

| tap | goes to |
|---|---|
| the notification itself | `obsidian://` — the project note in Austin's own app |
| button **Summary** | the same note rendered on github.com, for when the scheme doesn't resolve |
| button **Open run** | the Actions run page — last, because it is only useful when CI itself broke |

Ordering matters and was a real bug: **Open run** used to be the first and only button, so it
was the one pressed, and it deep-links into the GitHub mobile app and lands on a job list.

**Every line in the notification is `plain`, not `resultLine`** — the row's own jargon-free
sentence. Nothing re-summarises; N rows, N voices.

## Secrets

| secret | for |
|---|---|
| `ANTHROPIC_API_KEY` | opus tier |
| `OPENROUTER_API_KEY` | glm **and** deepseek tiers — one balance, not two |
| `ZAI_API_KEY` | glm fallback, if OpenRouter credit runs out |
| `LOOP_GH_TOKEN` | PAT (repo scope) to check out target repos and open PRs |

## Dry run

Costs nothing, proves routing and order:

```bash
pwsh ci/parse-spec.ps1 -Spec specs/omen-4.0.md -Out parsed.json
pwsh ci/run-spec.ps1 -Parsed parsed.json -WorkDir . -DryRun
```

## Self-checks

`.github/workflows/test.yml` runs all of these on every push. None spends a token, touches the
network, or needs a secret — which is why they gate rather than being something to remember.

```bash
pwsh ci/test-parse.ps1          # parse-spec.ps1: routing, order, both verify: dialects
pwsh ci/test-result-parse.ps1   # what a row is allowed to say about itself
pwsh ci/test-verify-core.ps1    # TopoOrder + Invoke-Verify: what runs, and what counts as passed
pwsh ci/test-pipeline.ps1       # checkoff.ps1 + vault-sync.ps1, on throwaway copies
bash  ci/test-notify.sh         # notify.sh, against a fake curl — sends nothing
python3 ci/test-price-watch.py  # price-watch.py, against canned prices
node  watchdog/check.test.js    # the watchdog's one boolean, against recorded runs
```

`ci/test-parse.md` is the parser fixture: 5 rows, 3 tiers, a dependency chain, one `[x]`, both
`verify:` dialects, and a `depends-on: everything`. It used to be checked by a human reading the
dry-run output; `ci/test-parse.ps1` asserts against it now.

These find real bugs. `ci/test-pipeline.ps1` caught a heading rebuilt as `### [x] T1 - - title`
before it shipped. `ci/test-price-watch.py` caught the price watcher advising Austin to replace
his coding tier with his own grunt model.

## What this replaced

| old | why it existed | now |
|---|---|---|
| `run-spec.js` (36k) | Claude Code Workflow orchestration | `ci/run-spec.ps1`, ~180 lines |
| `.run.lock` pid lock | two runs clobbering one tmp file | `concurrency:` |
| `loop-guard.ps1` | a run hung 4h15m unnoticed | `timeout-minutes:` |
| `queue/NIGHT.md` | serial, one PC, one budget | parallel matrix |
| `logs/nightly.log` | "did it actually run?" | the run log |
| OmniRoute + OpenRouter + `free-ladder` | free provider fallback pool | three direct keys |
| manual dispatcher session | someone had to babysit it | nobody |

`ci/parse-spec.ps1` is the one piece kept — deterministic regex, refuses to drop a row,
runs before a token is spent.

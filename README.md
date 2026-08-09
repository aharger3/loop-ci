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
pwsh ci/parse-spec.ps1 -Spec specs/omen-v3.2.md -Out parsed.json
pwsh ci/run-spec.ps1 -Parsed parsed.json -WorkDir . -DryRun
```

`ci/test-parse.md` is the parser self-check: 5 rows, 3 tiers, a dependency chain, one `[x]`,
both `verify:` dialects, and a `depends-on: everything`. Parse it and dry-run it — if the
printed order, tiers or verify commands change, something broke.

Two more, neither of which spends a token:

```bash
pwsh ci/test-result-parse.ps1   # what a row is allowed to say about itself
pwsh ci/test-pipeline.ps1       # checkoff.ps1 + vault-sync.ps1, on throwaway copies
```

`ci/test-pipeline.ps1` covers the two scripts that edit files by hand. It caught a real bug
before it shipped: rebuilding a `### T1 -- title` heading from its captured parts produced
`### [x] T1 - - title`.

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

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

target: one sentence on what this version is for.

### T1 -- do the thing
- model: opus
- depends-on: T0        (optional; `everything` means "runs last")

Prose describing the work.

- **done-when:** the test that proves it.
```

`done-when:` is mandatory. A row with no success test is refused before anything runs.

## Models

One binary, three env blocks. DeepSeek and Z.ai both publish Anthropic-compatible endpoints
built for Claude Code, so there is no gateway and no translation layer.

| `model:` tag | goes to | when |
|---|---|---|
| `opus`, `fable`, `claude` | `claude-opus-5` @ api.anthropic.com | judgment rows, while console credits last |
| `glm`, `z-ai/glm-5.2` | `glm-5.2` @ api.z.ai | becomes the top tier when credits run out |
| anything else, blank | `deepseek-v4-flash` @ api.deepseek.com | grunt work, cheapest |

**A row is never silently downgraded.** If its tier has no key, the row is *blocked* and you
get one notification with the exact command to fix it. Downgrading a judgment row onto a
cheap model is how a spec quietly produces confident garbage.

## Notifications

Four, ever, on topic `aharg-loop`:

| type | when |
|---|---|
| **start** | run began, with an ETA |
| **blocked** | a human task, with the exact steps to resume |
| **recommend** | some rows landed, some didn't — worth a look |
| **done** | finished, with a done/total count and a link |

The readable report is the run page, not the push notification. `ci/notify.sh` rejects any
type outside those four, so a fifth cannot be added by accident.

## Secrets

| secret | for |
|---|---|
| `ANTHROPIC_API_KEY` | opus tier |
| `DEEPSEEK_API_KEY` | deepseek tier |
| `ZAI_API_KEY` | glm tier |
| `LOOP_GH_TOKEN` | PAT (repo scope) to check out target repos and open PRs |

## Dry run

Costs nothing, proves routing and order:

```bash
pwsh ci/parse-spec.ps1 -Spec specs/omen-v3.2.md -Out parsed.json
pwsh ci/run-spec.ps1 -Parsed parsed.json -WorkDir . -DryRun
```

`ci/test-parse.md` is the self-check: 5 rows, 3 tiers, a dependency chain, one `[x]`, and a
`depends-on: everything`. Parse it and dry-run it — if the printed order or tiers change,
something broke.

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

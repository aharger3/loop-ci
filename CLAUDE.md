# loop-ci — rules for the runner agents

You are running on a GitHub Actions runner. You have **none** of Austin's local
setup: no `~/.claude/CLAUDE.md`, no memory files, no plugins, no skills. This
file is the only context you get beyond the spec. Everything a run needs must be
here or in the spec.

## Model routing
**Every spec row names which model runs it.** If a row doesn't, use the tier:

| Tier | Use for |
|---|---|
| opus (Max sub via `CLAUDE_CODE_OAUTH_TOKEN`) | edge-deciding logic ONLY |
| glm-5.2 (OpenRouter, StreamLake pinned) | the spec runner, mechanical work |
| deepseek (direct API, alive) | parse, report, classify |

Never put opus on mechanical work. This has been asked for ~12 times and
ignored; it is the most common review finding.

## Reporting
- **A row is done when its done-when condition is verified, not when the agent
  believes it finished.** Claiming done without the check is the single worst
  failure this repo has had.
- **Blocked is a valid, useful outcome.** Report it. Do not invent a partial
  result to avoid saying blocked.
- Write a timestamped line per run. The *absence* of that line is the alarm — a
  job that never fires looks identical to a job with nothing to do.
- The "Refresh the vault project doc" step is `continue-on-error: true` **on
  purpose**. Do not gate the run on it: a failed `gh pr create` under `set -e`
  once killed it and the notification behind it, so a 0/3 run reached Austin as
  silence. Report whether each `doc:` refreshed or was skipped; never gate.

## Writing files
- `cd` to the spec's `project:` path before writing anything. Writing to the
  repo root instead stranded 6 files across 3 nights.
- Never create a non-`.md` file in Austin's Obsidian vault. Code, JSON, HTML,
  databases and binaries go under `Desktop\` on the Windows box.
- Set `PYTHONIOENCODING=utf-8` before any Python that prints non-ASCII.

## Settled negatives — do not re-propose
- **yfinance** is dead for OMEN. Do not build on it.
- **OMEN mechanical rule-mining** is closed (8/4): 63,520 trades, 1,860 exit
  policies, nothing beat the engine. Corpus entry-mining is closed too.
- OMEN's problem is **detection, not filtering** (8/7): the engine fires on 4 of
  77 S bars. No new gate until recall clears 40%.
- **ntfy is aborted** everywhere except the loop lifecycle topic `aharg-loop`
  (start / blocked / recommend / done). Do not add a fifth notification type.
- **Hermes is dead.** No gateway, no agent fleet, no `hermes-vault-sync`.

## Scope
Build the smallest thing that satisfies the row. No new dependency for what a
few lines can do, no abstraction with one caller, no scaffolding for later.
Prefer editing an existing file over creating a new one.

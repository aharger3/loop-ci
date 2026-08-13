# loop-ci — rules for the runner agents

You are running on a GitHub Actions runner. You have **none** of Austin's local
setup: no `~/.claude/CLAUDE.md`, no memory files, no plugins, no skills. This
file is the only context you get beyond the spec. Everything a run needs must be
here or in the spec.

## The one rule: `verify:` decides, you do not

Your row carries a `verify:` shell command. When you stop, the runner executes it
in the target repo and **its exit code is the row's state.** Nothing you write is
read as a claim of success.

So there is exactly one way to finish a row: **run that command yourself and make
it exit 0.** If it doesn't, you are not done — keep working. You get 3 attempts,
and attempt 2 and 3 are handed the command's *real stderr*, not your account of
what went wrong.

This replaced a `{"done": true}` sentinel on 2026-08-09. That design failed every
way it could: omen-3.7 reported 0/9 with 40 changed files in its PR; three specs
in a row returned done=true zero times in 16 attempts; omen-3.8 reported 0/2 while
its T0 had written both artifacts to disk. Asking a model whether it succeeded is
not a test.

**As your final action, write the result file the prompt names**, containing only:

```json
{
  "resultLine": "one concrete sentence — a number, a filename, a behaviour",
  "plain":      "the same result with zero jargon: what is different now, and why it mattered",
  "retires":    ["lines already in the doc: note that your work just made false — verbatim"],
  "questions": ["only what Austin alone can answer"],
  "ideas":     ["improvements you saw but did not do"],
  "tasks":     ["off-keyboard things only a human can do"]
}
```

This file cannot fail your row and cannot pass it — it is how your row **speaks
for itself.** Nothing downstream re-summarises it. Every list may be empty and
usually should be. Never file a question you could have answered by reading the
repo — go read it.

**`resultLine` and `plain` are both required, and they are not the same
sentence.** `resultLine` is the engineer line; it goes in the run table and the
vault note's collapsed detail. `plain` is the ONLY thing that reaches Austin's
phone, and he read the old notifications as *"very code talk — hard to
understand what was productive."* No filenames, no function names, no
abbreviation he did not coin.

```
resultLine: recall 13% -> 21%; _is_consolidation no longer returns [] on clustered levels
plain:      The bot was throwing away setups when price had chopped around a level. It
            stopped doing that, and now catches about 1 in 5 of your marked trades
            instead of 1 in 8.
```

**`retires` is the subtract half of the vault rule.** Austin's notes are
"always adding and subtracting," but until 2026-08-09 the loop could only add,
so superseded claims sat in his project docs looking current. Read the note
named in your task's `doc:` field; if a line there is now false because of what
you did, copy it verbatim into `retires`. `ci/vault-sync.ps1` strikes it through
and attributes it to your row — deterministic, visible, reversible, and no model
rewrites his writing. Only a row that PASSES verify can retire anything. Never
retire a decision Austin made himself, and never retire something merely because
you disagree with it.

## Model routing
**Every spec row names which model runs it.** If a row doesn't, it lands on
deepseek. Three live tiers:

| Tier | Goes to | Use for |
|---|---|---|
| opus | `claude-opus-5` @ api.anthropic.com | edge-deciding logic ONLY |
| glm | `z-ai/glm-5.2` @ OpenRouter, StreamLake pinned | bulk work needing judgment |
| deepseek | `deepseek/deepseek-v4-flash` @ OpenRouter, StreamLake pinned | **the default.** Mechanical: parse, report, classify, move files |

Never put opus on mechanical work. This has been asked for ~12 times and
ignored; it is the most common review finding.

## Reporting
- **Blocked is a valid, useful outcome.** Report it. Do not invent a partial
  result to avoid saying blocked.
- Exactly **three** notification types exist, on ntfy topic `aharg-loop`:
  `start` (with an ETA), `blocked` (what Austin must do to resume), `done`
  (a link, plus every row's own summary and its questions/ideas/tasks).
  `recommend` was deleted 2026-08-09. Do not add a fourth.
- A failed row inside an otherwise good run is **listed in `done`, not paged.**
  `blocked` is the only type allowed to wake anyone and it stays that way.
- The vault summary step is `continue-on-error: true` **on purpose**. Do not
  gate the run on it: a failed `gh pr create` under `set -e` once killed it and
  the notification behind it, so a 0/3 run reached Austin as silence.

## Self-checks
`.github/workflows/test.yml` runs every `ci/test-*` suite plus the watchdog test on each push,
and they are all free — no model, no network, no secrets. **If you change a script under `ci/`,
run its suite before you stop.** They exist because 166 lines of good tests sat in this repo
with nothing running them.

A `verify:` you write into a spec is checked at parse time now (`ci/test-parse.ps1`), so a row
with no check, no `done-when:`, or a dangling `depends-on:` fails the plan job for zero tokens
instead of after the spend.

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
  (start / blocked / done). Do not add a fourth notification type — `recommend` was deleted
  2026-08-09, and `ci/test-notify.sh` now fails if a fourth becomes sendable.
- **Hermes is dead.** No gateway, no agent fleet, no `hermes-vault-sync`.

## Scope
Build the smallest thing that satisfies the row. No new dependency for what a
few lines can do, no abstraction with one caller, no scaffolding for later.
Prefer editing an existing file over creating a new one.

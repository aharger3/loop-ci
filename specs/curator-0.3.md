# CURATOR 0.3 - The curator writes the spec

status: ready
version: curator-0.3
repo: aharger3/obsidian-vault
doc: Projects/the-curator.md

target: Turn the curator from a grader into the thing that writes 90% of the next spec - it researches its own findable questions, drafts a real loop-ci spec for the top project, folds Slack answers back in, and posts one morning brief.

## Why this version exists

0.2 shipped and ran once (2026-08-16): 35 notes scored, median 52, 11 G1 contradictions,
one dispatch posted. It works and it changed nothing. Austin's exact objection: **"I don't
see how it makes specs better - there's just a skill to score them."** Correct. A score is
a measurement, and this project's whole promise was that when he picks a project the master
spec is already 90% written.

0.3 closes that. Four additions, one deletion of ambiguity:

1. **Research its own questions.** The rule "prove it isn't findable before filing an agent
   question" has been in the skill since 0.2 and has never been enforced, because the skill
   never had a research step. Now it does - glm-5.2 with the `:online` web plugin, capped at
   the top note, max 3 questions per run.
2. **Draft the spec.** Top actionable note produces `Resources/spec-drafts/<project>-<next>.md`
   in loop-ci spec format, `status: draft`. Austin reviews and `/run` promotes it. The
   curator never pushes and never runs a build.
3. **Fold the answers back.** The readback path (`last_dispatch_ts` -> `slack_read_thread`)
   was written in 0.2 and has never executed once. 0.3 makes it step 1 of every run and
   ships a self-test that proves it against a real thread.
4. **One morning brief to `#curator`.** night-worker keeps its own channel and its own
   brief - two briefs, two channels, deliberately not merged so one repo breaking cannot
   silence the other.

## Settled in grilling, 2026-08-18 - do not re-decide these

- **Host: Claude Code cloud routine, once daily.** Not the Windows box. The PC being on is
  not the constraint; availability is. Env vars `SLACK_BOT_TOKEN` and `SLACK_CHANNEL` are
  set on the routine, not in a file.
- **Spec drafts land in the vault, not in loop-ci.** A routine clones one repo. It writes
  `Resources/spec-drafts/`; `/run` moves the approved draft into `loop-ci/specs/`.
- **Research model is `z-ai/glm-5.2` + `:online`.** Cheaper than Haiku 4.5 ($1/$5) and
  Sonnet 5 ($2/$10) for bulk reading. Fable/Opus only on synthesis. Perplexity is out - no
  BYOK, settled.
- **Notifications are not an LLM.** `chat.postMessage` and ntfy are plain HTTP POSTs. The
  model writes the text; the transport is stdlib.
- **Slack = anything that asks a question. ntfy = alarms only, silence is the alarm.**
- **G1 lie handling stays: fix the note, file a human task, never fix the thing.**

## Structure this version imposes

`.claude/skills/curate/SKILL.md` stays the short spine. Each new capability is its own
reference file the spine links to, so future versions edit one file each instead of five
rows fighting over one document.

```
.claude/skills/curate/
  SKILL.md                    <- the spine, v0.3, links out
  references/research.md      <- T2
  references/spec-draft.md    <- T3
  references/brief.md         <- T4
  references/readback.md      <- T5
  references/hosting-env.md   <- T6
  selftest.py                 <- T7
```


### [x] T1 -- Rewrite SKILL.md as the v0.3 spine
- model: glm

Rewrite `.claude/skills/curate/SKILL.md`. Keep the existing frontmatter `name: curate` and
keep the description accurate to the new behaviour. Keep every rule under "The rules that
protect the work" and "Never" verbatim - those are settled decisions and this row may not
change them.

The body becomes a numbered pipeline of exactly eight steps, in this order, each a short
paragraph that links to its reference file where one exists:

1. **Read answers back** (`references/readback.md`) - first, before anything else.
2. **Load reality** - `Resources/reality-latest.md`. Unchanged from 0.2, except: if the
   snapshot frontmatter `date` is more than 48h old, cap every G1 at 20/40 **and** post a
   one-line warning to `#curator` naming the snapshot age. The run still ships.
3. **Read every note** - `Projects/**/*.md` only, skip files starting with `_`.
4. **Grade 0-100** on the four gates. Table unchanged.
5. **Research the findable questions** (`references/research.md`).
6. **Generate** 🤖 / 💡 / 🧍 into each note. Four lenses unchanged.
7. **Write `Resources/project-scores.md`** - the build queue. Unchanged.
8. **Dispatch ONE project, draft its spec, post the brief**
   (`references/spec-draft.md`, `references/brief.md`).

Add a line stating the version is 0.3 and the host is a once-daily Claude Code cloud
routine, linking `references/hosting-env.md`.

- **done-when:** SKILL.md describes all eight steps in order, links all five reference
  files, still contains the never-change-a-decision rule and the PM2_ENV_ALLOW warning, and
  says version 0.3.
- **verify:**
  ```bash
  grep -q "0.3" .claude/skills/curate/SKILL.md
  grep -q "references/readback.md" .claude/skills/curate/SKILL.md
  grep -q "references/research.md" .claude/skills/curate/SKILL.md
  grep -q "references/spec-draft.md" .claude/skills/curate/SKILL.md
  grep -q "references/brief.md" .claude/skills/curate/SKILL.md
  grep -q "references/hosting-env.md" .claude/skills/curate/SKILL.md
  grep -q "never change a decision\|may NEVER change a decision" .claude/skills/curate/SKILL.md
  grep -q "PM2_ENV_ALLOW" .claude/skills/curate/SKILL.md
  ```

### [x] T2 -- Write references/research.md - the curator answers its own findable questions
- model: glm

Create `.claude/skills/curate/references/research.md`.

It defines the research step. The contract:

- Runs on **`z-ai/glm-5.2` with the `:online` web plugin**. Name the model string in the
  file. Synthesis of a contradictory result may escalate to Fable; bulk reading may not.
- **Scope cap: the top-scoring actionable note only, maximum 3 questions per run.** State
  the reason in the file - 35 notes times web searches is real money spent on notes nobody
  is building.
- A question is **findable** if the answer exists in public documentation, in a price list,
  in the vault, or on the Windows box. It is **Austin's** if it is a preference, a spend, an
  irreversible action, a career or physical task. Only the second kind may become a
  🤖 Agent Question. Give three worked examples of each.
- Answers are written into the note's **🔬 Research** section with the source URL on the
  same line, and the corresponding 🤖 question is deleted, not marked answered - it was
  never his to answer.
- If research is inconclusive after one pass, it stops and files the 🤖 question with what
  it learned attached. It does not loop.

- **done-when:** the file exists, names `z-ai/glm-5.2` and `:online`, states the 3-question
  and top-note-only caps, and gives worked examples on both sides of the findable line.
- **verify:**
  ```bash
  test -s .claude/skills/curate/references/research.md
  grep -q "z-ai/glm-5.2" .claude/skills/curate/references/research.md
  grep -q ":online" .claude/skills/curate/references/research.md
  grep -qi "maximum 3\|max 3\|3 questions" .claude/skills/curate/references/research.md
  grep -q "🔬" .claude/skills/curate/references/research.md
  ```

### [x] T3 -- Write references/spec-draft.md - the output that makes this project worth having
- model: glm

Create `.claude/skills/curate/references/spec-draft.md`.

This is the reason 0.3 exists. It defines how the curator turns the top actionable note into
a real loop-ci spec draft.

The contract:

- **Output path:** `Resources/spec-drafts/<project>-<next-version>.md` in the vault. Never
  `loop-ci/specs/`. Never pushed. Explain why in one line: a cloud routine clones one repo,
  and pushing a spec is `/run`, which is Austin's command and only his.
- **Frontmatter/header block must be `status: draft`**, plus `version:`, `repo:`,
  `doc:` pointing at the source note, and a one-sentence `target:`.
- **Row format is the loop-ci dialect** - `### T<n> -- <imperative title>`, a
  `- model:` line, optional `- depends-on:`, prose naming exact files, then `- **done-when:**`
  and `- **verify:**`. Reproduce the format skeleton in this file so the drafting model has
  it in front of it.
- **Every row must carry a `verify:` that fails on garbage.** `git diff --quiet` and any
  check that passes on an empty edit are banned by name. If the curator cannot write a
  verify for a row, it does not write the row - it writes that gap into the note's 🤖
  section as "this cannot be specced until X is decided" and the draft ships shorter.
- **Model tiering:** deepseek is the default and most rows land there; glm for multi-file
  judgment; opus only where a wrong answer corrupts silently. A draft that is all opus is
  mis-tiered and must be redone.
- **Cap 10 rows.** Prefer rows with no `depends-on` so they run wide.
- Next version number comes from the note's `version:` frontmatter incremented at the minor
  position, unless the note names its own next version.
- The draft's existence is announced in the morning brief and nowhere else.

- **done-when:** the file exists, contains the literal row skeleton with `done-when` and
  `verify`, bans `git diff --quiet` by name, states the `Resources/spec-drafts/` output path
  and `status: draft`, and states the 10-row cap.
- **verify:**
  ```bash
  test -s .claude/skills/curate/references/spec-draft.md
  grep -q "Resources/spec-drafts/" .claude/skills/curate/references/spec-draft.md
  grep -q "status: draft" .claude/skills/curate/references/spec-draft.md
  grep -q "git diff --quiet" .claude/skills/curate/references/spec-draft.md
  grep -q "done-when" .claude/skills/curate/references/spec-draft.md
  grep -q "verify" .claude/skills/curate/references/spec-draft.md
  grep -qi "10 rows\|ten rows" .claude/skills/curate/references/spec-draft.md
  ```

### T4 -- Write references/brief.md - the 08:00 post to #curator
- model: deepseek

Create `.claude/skills/curate/references/brief.md`.

Defines the single morning post to `#curator` (`C0BQ3QW9747`) via `slack_post`, as username
**Curator**. Exactly five blocks, in order, and nothing else:

1. **Three non-negotiables** for today, each under two hours and naming one concrete step.
2. **The dispatched project** - name, one-line summary, its `Next build step`.
3. **Its open 🤖 questions** as numbered multiple choice, **recommendation first**.
4. **New G1 contradictions since the last run only** - not the standing list. If none, one
   line saying so.
5. **The spec draft**, if one was written: its path and row count, one line.

Rules the file must state:

- **No digest.** One project. Never a menu of others.
- **Never re-ask an answered question.**
- night-worker keeps its own 08:00 brief in `#night-worker`. These are deliberately not
  merged - one repo breaking must not silence the other. Say so.
- The `thread_ts` of this post is written to `Resources/project-scores.md` frontmatter as
  `last_dispatch_ts` so the next run can read the replies.
- ntfy is not used here. ntfy carries alarms only.

- **done-when:** the file exists, names channel `C0BQ3QW9747` and `slack_post`, lists the
  five blocks, states recommendation-first, states `last_dispatch_ts` is written, and states
  the two briefs stay separate.
- **verify:**
  ```bash
  test -s .claude/skills/curate/references/brief.md
  grep -q "C0BQ3QW9747" .claude/skills/curate/references/brief.md
  grep -q "slack_post" .claude/skills/curate/references/brief.md
  grep -q "last_dispatch_ts" .claude/skills/curate/references/brief.md
  grep -qi "recommendation first" .claude/skills/curate/references/brief.md
  grep -qi "night-worker" .claude/skills/curate/references/brief.md
  ```

### [x] T5 -- Write references/readback.md - fold Slack answers into the notes
- model: glm

Create `.claude/skills/curate/references/readback.md`.

This path was written in 0.2 and has never executed. Define it precisely enough that it runs
unattended:

- Read `last_dispatch_ts` from `Resources/project-scores.md` frontmatter. If absent or the
  literal string `null`, skip readback and say so in the report. Do not error.
- Call `slack_read_thread(channel, ts)` and take **only human replies** - skip any message
  whose `bot_id` is set or whose username is Curator, or the curator reads its own post as
  an answer.
- Match a reply to a question by its number. A reply of "2" answers question 2. Free text
  that names no number is folded into the note as a decision paragraph rather than dropped.
- Write the decision into the **body** of the note that asked, dated, then mark that
  question `[x]`. Both, not one - a checked box with no recorded decision is how the answer
  gets lost.
- **Never re-ask an answered question**, and never un-check a box.
- After a successful fold, append a `readback` line to the score history so a run that
  folded nothing is visible.

Also state the failure this closes: `last_dispatch_ts` has held a real timestamp since
2026-08-16 and no run has ever read it.

- **done-when:** the file exists, names `slack_read_thread` and `last_dispatch_ts`, states
  the bot-message filter, states that both the body decision and the `[x]` are written, and
  states the skip-on-missing-ts behaviour.
- **verify:**
  ```bash
  test -s .claude/skills/curate/references/readback.md
  grep -q "slack_read_thread" .claude/skills/curate/references/readback.md
  grep -q "last_dispatch_ts" .claude/skills/curate/references/readback.md
  grep -qi "bot_id\|bot message\|its own post" .claude/skills/curate/references/readback.md
  grep -q "\[x\]" .claude/skills/curate/references/readback.md
  ```

### [x] T6 -- Write references/hosting-env.md - the routine and its environment
- model: deepseek

Create `.claude/skills/curate/references/hosting-env.md`.

One page that answers "where does this run and what does it need," so no future session
re-derives it:

- **Host: a Claude Code cloud routine, once daily.** Not the Windows box, not GitHub
  Actions, not pm2. The reason: the curator needs judgment and vault git writes, and must
  fire whether or not the PC is on.
- **A routine carries git repos, env vars and connectors. It does NOT carry**
  `~/.claude/skills`, `~/.claude/agents`, the global `CLAUDE.md`, or `~/.claude/mcp.json`.
  This is why the skill lives in the vault repo and the Slack MCP server is declared in
  `.mcp.json` at the repo root.
- **Env vars the routine must have set**, in a table: `SLACK_BOT_TOKEN` (bot token, from
  `keys.py`, scopes `chat:write`, `chat:write.customize`, `channels:history`,
  `groups:history`, `reactions:write`) and `SLACK_CHANNEL` (defaults to `C0BQ3QW9747`).
  State that these are set on the routine, never committed.
- **Channel map:** `#curator C0BQ3QW9747`, `#omen C0BQFGB61M3`, `#night-worker C0BQK5RUXL2`.
  One bot app, identity is the per-message `username`/`icon_emoji` field.
- **Surfaces:** Slack for anything that asks a question; ntfy (`aharg-nw`) for machine
  alarms only; Remote Control is disqualified because it dies when `ANTHROPIC_BASE_URL` is
  not `api.anthropic.com`.
- **What the curator never does:** push to `loop-ci`, run a build, or fix a dead process.

- **done-when:** the file exists, names both env vars, states the routine does not carry
  `~/.claude/skills`, lists all three channel IDs, and states ntfy is alarms-only.
- **verify:**
  ```bash
  test -s .claude/skills/curate/references/hosting-env.md
  grep -q "SLACK_BOT_TOKEN" .claude/skills/curate/references/hosting-env.md
  grep -q "SLACK_CHANNEL" .claude/skills/curate/references/hosting-env.md
  grep -q "C0BQ3QW9747" .claude/skills/curate/references/hosting-env.md
  grep -q "C0BQFGB61M3" .claude/skills/curate/references/hosting-env.md
  grep -q "C0BQK5RUXL2" .claude/skills/curate/references/hosting-env.md
  grep -q "~/.claude/skills" .claude/skills/curate/references/hosting-env.md
  ```

### T7 -- selftest.py - a gate that fails when the skill loses a piece
- model: deepseek
- depends-on: everything

Create `.claude/skills/curate/selftest.py`. Python 3 stdlib only, no network, no LLM. It
asserts the skill is structurally whole and exits nonzero with a named reason when it is not:

1. `SKILL.md` exists and links all five reference files; each linked file exists and is
   non-empty.
2. `SKILL.md` still contains the never-change-a-decision rule and the `PM2_ENV_ALLOW`
   warning - a regression here means a run rewrote a settled rule.
3. `Resources/project-scores.md` exists and its frontmatter parses, with a `last_dispatch_ts`
   key present (value may be empty).
4. `Resources/reality-latest.md` exists; print its age in hours and print
   `SNAPSHOT_STALE` when over 48h. **Stale is a warning, not a failure** - a broken probe
   must not also break the curator.
5. `Resources/spec-drafts/` exists as a directory.

Print one line per check, `ok` or `FAIL: <reason>`, then a final `selftest: N/5 ok`.

Also create `Resources/spec-drafts/.gitkeep` so the directory survives a clone.

- **done-when:** `python3 .claude/skills/curate/selftest.py` exits 0 and prints `5/5 ok`
  against the repo as this spec leaves it.
- **verify:**
  ```bash
  test -d Resources/spec-drafts
  python3 .claude/skills/curate/selftest.py
  python3 .claude/skills/curate/selftest.py | grep -q "5/5 ok"
  ```

### T8 -- Update the project note to 0.3
- model: deepseek

Edit `Projects/the-curator.md`. Do not rewrite the history sections - add and correct only.

1. **Correct the false claim at the top.** The note says v0.2 "never ran." It ran:
   `Resources/project-scores.md` has `run: 1`, `date: 2026-08-16`, 35 notes scored, 1
   spec-ready, 11 G1 contradictions, median 52, and a real `last_dispatch_ts`. Replace the
   stale status with a truthful one. This is the curator's own G1 gate applied to the
   curator's own note - say that in one line.
2. Bump frontmatter to `version: 0.3.0`, `date: 2026-08-18`, keep `status: spec-ready`.
3. Add a `## Status — 2026-08-18: v0.3` section covering the four additions (readback,
   research, spec draft, morning brief), the file layout under
   `.claude/skills/curate/references/`, and every line under "Settled in grilling" from this
   spec so no future session re-decides them.
4. Answer the three stale 🤖 Agent Questions in place and mark them `[x]` - all three were
   settled long ago: fix the note and file a human task; `Projects/` only; plain table.
5. Replace `Next build step` with: set `SLACK_BOT_TOKEN` and `SLACK_CHANNEL` on the daily
   cloud routine, run `/curate` once by hand, reply to the dispatched thread once, then
   confirm the next run folded the answer in - the live readback self-test.
6. Add to `🧍 Human Tasks`: reply once in the `#curator` thread so the readback path is
   proven against real Slack, and fix the failing `NightWorker` scheduled task so
   `reality-latest.md` stops aging past 48h.

- **done-when:** the note says version 0.3.0, no longer claims v0.2 never ran, has a
  2026-08-18 status section, has zero unchecked boxes in 🤖 Agent Questions, and its
  `Next build step` names the routine env vars and the live readback test.
- **verify:**
  ```bash
  grep -q "version: 0.3.0" Projects/the-curator.md
  grep -q "2026-08-18" Projects/the-curator.md
  ! grep -q "never yet run\|not yet run\|never ran" Projects/the-curator.md
  grep -q "SLACK_BOT_TOKEN" Projects/the-curator.md
  test "$(sed -n '/## 🤖 Agent Questions/,/^## /p' Projects/the-curator.md | grep -c '^- \[ \]')" = "0"
  ```

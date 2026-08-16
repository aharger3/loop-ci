# RESPONDER 0.1.0 - One daemon, a persona per Slack channel, instant replies

status: ready
version: responder-0.1.0
repo: aharger3/responder
doc: Projects/agents/agent-hosting.md

target: Turn Slack from a mailbox into a listening agent - one always-on process on the Windows box that watches #night-worker, #omen and #curator, reacts within seconds so Austin knows it was read, answers in the thread as that channel's persona, and changes nothing else.

## Why this version exists

Slack is live and posting. Nothing reads it back. Today a reply sits in a thread until a
human opens a Claude session and asks - which is a mailbox, not an agent, and it is the
reason Austin cannot yet get "an OMEN bot that works on its own."

The gap he named is narrower than it sounds: **he cannot tell whether a message was read.**
So the first deliverable is not intelligence, it is a receipt. A `:eyes:` reaction within
seconds, a threaded answer, then `:white_check_mark:`. Everything else in this version
exists to make that loop honest.

## Prior art - checked, nothing to fork

Researched 2026-08-16. Nobody has shipped "team of agents, one per channel" as a maintained
project. `mpociot/claude-code-slack-bot` (~150 stars, MIT, TypeScript, Socket Mode) has the
best daemon shape and thread-session handling; `jeremylongshore/claude-code-slack-channel`'s
`000-docs/multi-agent-channels.md` is the best written description of channel-to-persona
routing. Anthropic's own Claude Tag is confirmed unable to run a user's own personas.

**We take the shape, not the code.** Python, not TypeScript - everything else on the box is
Python and the point is one runtime, not a second one.

## Settled - never re-elicit

1. **One process, N identities.** Identity is not in the daemon. It is the persona markdown
   the daemon loads for that channel, plus a per-channel Claude session id. A responder per
   agent would be N processes and N watchdogs - the same mistake as a bot app per agent.
2. **Polling, not Socket Mode, in 0.1.** `conversations.history` every 20 s works with the
   28 scopes the bot already has and needs nothing from Austin. Socket Mode needs him to
   generate an `xapp-` app-level token in the Slack UI; the transport is one swappable
   function so that upgrade is a later, small change.
3. **Read, react, answer. It writes nothing else in 0.1.** No vault edits, no loop-ci
   pushes, no config changes. Those get powers in 0.2 once this loop is proven honest.
4. **Personas live in `~/.claude/agents/<name>.md`**, Syncthing-mirrored, and a copy is
   bundled in this repo under `agents/` so a fresh clone runs. The repo copy is the
   fallback, the home directory wins when both exist.
5. **glm is the default model; the persona file overrides it.** `#omen` gets opus because a
   wrong trading answer is the kind that silently costs money. Which model is *best value*
   stops being a hand-made constant once the model-value scanner exists - see
   `Projects/model-value-scanner.md` - so read the model from the persona, never hardcode.
6. **Silence is a valid answer.** `:eyes:` with no reply is allowed and must not be treated
   as a failure.

## Known channels

| Channel | id | Persona | Model |
|---|---|---|---|
| `#night-worker` | `C0BQK5RUXL2` | night-worker | glm |
| `#omen` | `C0BQFGB61M3` | omen | opus |
| `#curator` | `C0BQ3QW9747` | curator | glm |

Bot user is `vault_agents`; the token is in `.slack-token` beside the code, already
gitignored. Never print it, never put it in a log line or an error message.


### T1 -- slackio.py: the transport, with the read receipt
- model: deepseek

New `slackio.py`. Stdlib only (`urllib`, `json`, `os`, `time`). Every Slack call goes
through here so the rest of the daemon never touches HTTP.

Functions: `read_new(channel) -> list[dict]`, `post(channel, text, thread_ts, username,
icon_emoji) -> str|None`, `react(channel, ts, emoji)`, `unreact(channel, ts, emoji)`.

`read_new` calls `conversations.history` with `oldest` set from a **cursor file**
(`cursor.json`, `{channel_id: last_ts}`, written after every successful read). A restart
must never re-answer a backlog - that is the single worst failure mode of a bot that talks.
Fetch thread replies too: for any returned message carrying `thread_ts`, pull
`conversations.replies` so answers inside a thread are seen, not just top-level posts.

**Every message with a `bot_id`, or a `subtype`, or a `user` equal to our own bot user id,
is dropped before it is returned.** A daemon that answers itself loops forever and bills
both halves. Resolve our own bot user id once at startup via `auth.test` and cache it.

The token resolves from `RESPONDER_SLACK_TOKEN`, falling back to a `.slack-token` file
beside the script - the same pattern night-worker already uses. `RESPONDER_DISABLE_IO=1`
makes every function a no-op returning empty/None without opening a socket.

All Slack calls go through one `_call(method, payload)` that retries twice on a 429 or a
5xx with the `Retry-After` header honoured, and returns `None` rather than raising on
anything else. Rate-limit failures must never kill the loop.

Write `tests/test_slackio.py` using a fake transport injected into `_call` - no sockets.
Cover: the cursor advances and a second read returns nothing; a message with `bot_id` is
dropped; a message from our own user id is dropped; thread replies are included; a 429 is
retried and then succeeds; `RESPONDER_DISABLE_IO=1` opens no socket.

- **done-when:** `python -m pytest tests/test_slackio.py -q` passes with no network access,
  and re-reading after a cursor write returns zero messages.
- **verify:**
  ```bash
  python -m pytest tests/test_slackio.py -q
  grep -q 'bot_id' slackio.py
  grep -q 'cursor.json' slackio.py
  ```


### T2 -- personas.py plus the three agent markdown files
- model: deepseek

New `personas.py` and a new `agents/` directory holding `night-worker.md`, `omen.md`,
`curator.md`.

Each persona file is YAML frontmatter (`name`, `channel`, `model`, `username`,
`icon_emoji`) followed by the system prompt in prose. Write the three:

- **night-worker** - `C0BQK5RUXL2`, model `glm`, `:crescent_moon:`. Knows it reports on an
  overnight corpus worker on a Windows box: three stages, local Ollama models, a JSONL log.
  Answers about last night's numbers. Never claims a number it was not given.
- **omen** - `C0BQFGB61M3`, model `opus`, `:chart_with_upwards_trend:`. Trading system Q&A.
  Standing rule: it may explain and propose, it may never state a fill, a P&L or a recall
  figure it did not read from a file.
- **curator** - `C0BQ3QW9747`, model `glm`, `:card_index_dividers:`. Talks about project
  scores and what to build next.

Every persona ends with the same three standing rules, written out in each file rather than
injected, so a file read in isolation is complete: keep replies short - Austin has ADHD and
reads on a phone; say "I don't know" rather than inventing a number; never claim to have
done something the daemon cannot do in this version (it cannot edit notes or push builds).

`personas.py` exposes `load(channel_id) -> dict` which prefers
`~/.claude/agents/<name>.md` and falls back to this repo's `agents/<name>.md`, returning
frontmatter fields plus `prompt`. Unknown channel returns `None` - an unrecognised channel
is ignored, never answered by a default persona.

`channels.json` in the repo root maps channel id to persona name, and is the only place ids
appear. Adding an agent must be one row here plus one markdown file, nothing else.

Write `tests/test_personas.py`: each of the three channel ids loads, the model field is
`glm`/`opus`/`glm` respectively, an unknown id returns `None`, and a file in a fake home
directory beats the repo copy.

- **done-when:** `python -m pytest tests/test_personas.py -q` passes and all three persona
  files parse with a non-empty prompt.
- **verify:**
  ```bash
  python -m pytest tests/test_personas.py -q
  test -s agents/night-worker.md
  test -s agents/omen.md
  test -s agents/curator.md
  grep -q 'C0BQFGB61M3' channels.json
  ```


### [x] T3 -- runner.py: invoke claude -p as the persona, one session per channel
- model: glm

New `runner.py`. `ask(persona, text, channel) -> str|None` shells out to the `claude` CLI in
non-interactive mode and returns the reply text.

Build the invocation as an argv **list** passed to `subprocess.run` - never a joined string.
An earlier bug on this box (`Start-Process -ArgumentList`) split a prompt on spaces so the
model received a single word; the list form is the fix and it is not optional. Feed the
user's message on **stdin**, pass the persona prose via the system-prompt flag, and select
the model from the persona's `model` field.

**Per-channel session continuity.** Keep `sessions.json` mapping channel id to the session
id `claude` reports. Resume that session on the next message in the same channel so `#omen`
never sees `#night-worker`'s conversation. If a resume fails for any reason, start a fresh
session, log it, and carry on - a lost session is a worse answer, not an outage.

Guards, all of them required because this runs unattended:

- a hard `timeout` (default 180 s) - on expiry return `None`, never hang the loop;
- a maximum reply length, truncated with a marker, so a runaway generation cannot post a
  wall of text to a phone;
- non-zero exit or empty stdout returns `None`, and `None` means *post nothing*;
- the persona's model name maps through one table to the actual model id, and an unknown
  model name falls back to glm with a logged warning rather than crashing.

Make the subprocess injectable (`run_fn`) exactly as `stagec.py` does with its `deps`, so
every test runs with no CLI and no network.

Write `tests/test_runner.py` with a fake `run_fn`: argv is a list and the prompt survives
intact with its spaces; the system prompt contains the persona prose; a second call to the
same channel resumes the recorded session id; a different channel does not; a timeout
returns `None`; empty stdout returns `None`; an over-long reply is truncated.

- **done-when:** `python -m pytest tests/test_runner.py -q` passes and no test spawns a real
  process.
- **verify:**
  ```bash
  python -m pytest tests/test_runner.py -q
  grep -q 'sessions.json' runner.py
  grep -q 'timeout' runner.py
  ```


### T4 -- responder.py: the loop that ties it together
- model: glm
- depends-on: T1, T2, T3

New `responder.py`, the entry point. It imports `slackio`, `personas` and `runner` - it
implements no HTTP and no subprocess logic of its own.

The loop, every `RESPONDER_POLL_SECONDS` (default 20):

1. For each channel in `channels.json`, `slackio.read_new`.
2. For each message: load the persona; if `None`, skip. React `:eyes:` **immediately**,
   before the model is called - the receipt is the product, and it must not wait on a slow
   answer.
3. `runner.ask`. On a non-empty reply, `slackio.post` into that message's thread
   (`thread_ts` = the parent's ts, or the message's own ts if it is top-level) using the
   persona's `username` and `icon_emoji`. Then remove `:eyes:` and add
   `:white_check_mark:`.
4. On `None`, leave `:eyes:` in place and add no reply. Silence is a valid outcome and
   `:eyes:`-without-a-tick is the honest signal for it.

Hard safety rails, all of them:

- **one reply per thread per 60 s**, tracked in memory - a stuck loop that posts is worse
  than one that dies;
- **a daily reply cap** (default 200) after which it reacts but stops answering and logs
  `cap-reached` once;
- every iteration wrapped so **one bad channel cannot stop the others**;
- one JSONL line per message handled to `responder.log` - channel, ts, persona, latency,
  outcome (`answered` / `silent` / `error`), and never the message text or the token.

`--once` runs a single poll cycle and exits, for testing and for a by-hand check.
`--dry-run` reacts and reasons but posts nothing.

Write `tests/test_responder.py` driving the whole loop with all three modules faked:
`:eyes:` is added before the runner is called; a successful answer posts in-thread and ends
with `:white_check_mark:`; a `None` answer posts nothing and leaves `:eyes:`; a second
message in the same thread inside 60 s is not answered; a channel that raises does not stop
the next channel; the daily cap stops replies but not reactions.

- **done-when:** `python -m pytest tests/test_responder.py -q` passes and
  `python responder.py --once --dry-run` exits 0 with `RESPONDER_DISABLE_IO=1` set, opening
  no socket and spawning no process.
- **verify:**
  ```bash
  python -m pytest tests/test_responder.py -q
  RESPONDER_DISABLE_IO=1 python responder.py --once --dry-run
  ```


### [x] T5 -- Install it on the box so it survives a reboot
- model: deepseek

New `install.ps1`, **ASCII-only** - non-ASCII characters in a `.ps1` on this box become
parse errors, which cost an hour once already.

Register a scheduled task named `Responder` with `Register-ScheduledTask`, `-LogonType
Interactive`, `-RunLevel Highest`, `MultipleInstances IgnoreNew`, triggered **at startup
plus two minutes** and running `python responder.py` from the repo directory. That trigger
form is the one proven to work unattended here - `schtasks /create /np` refuses to pair with
`/rl highest`.

Add a `Responder-Watchdog` task on a five-minute repeat that starts `Responder` if it is not
running, mirroring the existing `OllamaKeepAlive` pattern. A daemon whose whole value is
being awake needs a watchdog; a crash that goes unnoticed until morning is the failure this
version exists to end.

The script must be idempotent - re-running it re-registers cleanly over an existing task,
because that is how it gets deployed. It must not create, remove or reschedule any other
task, and it must not add a cron of any kind.

Print the exact command to check status and the exact command to tail `responder.log`, so
the README can quote them rather than inventing them.

The runner cannot reach the box, so the check is a parser gate, not an execution:
`tests/parse-ps1.ps1` must dot-source nothing and simply parse every `.ps1` in the repo with
the real PowerShell parser and fail on any error.

- **done-when:** `pwsh tests/parse-ps1.ps1` exits 0 with `install.ps1` in the parse set and
  `install.ps1` contains no non-ASCII byte.
- **verify:**
  ```bash
  pwsh tests/parse-ps1.ps1
  ! LC_ALL=C grep -qP '[^\x00-\x7F]' install.ps1
  grep -q 'Responder-Watchdog' install.ps1
  ```


### T6 -- README and the one thing Austin has to do himself
- model: deepseek
- depends-on: everything

Rewrite `README.md` to describe what this actually is: one always-on process, a persona per
Slack channel, `:eyes:` on read and `:white_check_mark:` on answered, polling every 20 s.

It must include: the channel-to-persona table; how to add an agent (one row in
`channels.json`, one markdown file in `agents/`, nothing else); every environment variable
(`RESPONDER_SLACK_TOKEN`, `RESPONDER_POLL_SECONDS`, `RESPONDER_DISABLE_IO`,
`RESPONDER_DAILY_CAP`); the by-hand commands from T5; and an explicit statement of what
0.1 **cannot** do - it does not edit vault notes, does not push loop-ci specs, and does not
change any config.

Add a short **Upgrade to Socket Mode** section naming the exact manual step, because it is
the only thing here a human must do: at api.slack.com, open the Vault Agents app, enable
Socket Mode, generate an app-level token with `connections:write`, subscribe the bot to the
`message.channels` event, and store the `xapp-` token as `RESPONDER_APP_TOKEN`. Say plainly
that polling works without it and this is a latency upgrade, not a fix.

Confirm `.gitignore` covers `.slack-token`, `sessions.json`, `cursor.json` and
`responder.log`, and add whichever are missing. A session file or a cursor in git is a
correctness bug, not just noise.

- **done-when:** the full test suite and the parser gate both pass, and `README.md` names
  all three channel ids, the two reaction emoji and `connections:write`.
- **verify:**
  ```bash
  python -m pytest tests/ -q
  pwsh tests/parse-ps1.ps1
  grep -q 'C0BQK5RUXL2' README.md
  grep -q 'connections:write' README.md
  grep -q 'white_check_mark' README.md
  grep -q 'sessions.json' .gitignore
  ```

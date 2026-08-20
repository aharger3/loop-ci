# EV-DASHBOARD 0.6 - The notification path, end to end

status: ready
version: ev-dashboard-0.6
repo: aharger3/ev-dashboard
doc: Projects/ev-dashboard.md

target: Turn the board from a page nobody opens into a phone notification that names a +8% play and links straight to its row, plus the CLV tool that says whether any of it is worth pushing.

## Why this version exists

The 2026-08-19 grilling settled that **the notification is the product**. A dashboard
Austin has to remember to open is a dashboard he does not open. The board already
computes plays correctly (phantom +446% rows died in `1637d88`); what is missing is the
path from a computed edge to a tappable link on a lock screen.

Three things block that today and all three are code in this repo:

1. **`_ntfy()` returns on line 1.** The 2026-08-02 VOID killed every push. That VOID was
   correct for what existed then — untargeted spam at every EV level. It is reversed
   *narrowly*: `aharg-ev` digest at **+8% and up only**, one message per pull.
2. **A notification's link has no destination.** There is no per-row anchor in the
   template, so the best a push can do is drop him at the top of a 40-row board.
3. **`app.py:76` hardcodes `b.setdefault("states", "NC")`.** Every row claims NC, so the
   `f-state` filter in the UI is decoration. Pushing a play he legally cannot enter is
   worse than pushing nothing.

And underneath all of it: 98,665 rows of `hist_lines` bought with 20,000 credits, and no
tool that reads them. The 2026-08-19 closing-line burn added the T-15m rung specifically
so CLV is computable. Nothing has computed it.

## Settled in the 2026-08-19 grilling — never re-elicit

1. **ntfy, topic `aharg-ev`.** Not Discord, not email. ntfy is the only channel in the
   stack that renders a tappable action button on a locked phone.
2. **+8% EV and above, one digest per pull.** Below 8% goes to the board only.
3. **Action button target = the play's own dashboard row**, not the board top.
4. **Widen the live pull, bank the rest.** Current caps spend ~72 credits/pull ≈ 4,400 of
   a 20,000 monthly quota. Widening is the decision; the reserve is the leftover.
5. **`verify_in_app` plays are marked suspect in the push**, never rendered as a headline
   number. An implausible EV is a data bug until a human sees the app.
6. **Raw storage stays raw.** The devig model will change; the credits to re-derive
   `hist_lines` will not exist.
7. **The board loads the gun; Austin pulls the trigger.** No auto-placement, ever.

## What the runner cannot do — read this before writing a verify

`ev_ledger.db` is **gitignored** (47 MB, `.gitignore` line 3). The runner has no database
and no `ODDS_API_KEY`. Every row here must therefore verify **offline**, against
`fixtures/` or a fixture DB the row builds itself. `python run.py --fixture` works with no
key and no network and writes `latest.json` — it is the standard offline entry point.

`backfill.py` and `close_burn.py` exist on the Windows box but are **untracked**. Do not
write a row that imports them.


### [x] T1 -- Re-enable the ntfy digest at +8%, one message per pull
- model: glm

In `run.py`:

Delete the early `return` at the top of `_ntfy()` (the 2026-08-02 VOID stub) so the
function actually sends. Leave the VOID comment in place but rewrite it to say the abort
was reversed on 2026-08-19 and why — a future session must not re-void it by reading a
stale comment.

Add `DIGEST_MIN_EV = 8.0` next to `ALERT_LEG_EV`. Add a pure function
`digest_lines(scored) -> list[str]` that takes the scored plays and returns one line per
play whose `ev_pct >= DIGEST_MIN_EV`, sorted highest EV first, capped at 6 lines. A play
carrying `verify_in_app: True` is prefixed with `"[UNVERIFIED] "` and its EV is rendered in
parentheses as `(unverified +X%)` rather than as a bare headline number. Plays below the
threshold never appear.

Change the digest call at the bottom of `main()` so that when `digest_lines()` returns
nothing, **no push is sent at all** (a silent pull is correct — do not send "0 plays").
When it returns lines, send one ntfy to `NTFY_EV_CHANNEL` whose body is those lines joined
by newlines, and whose action button points at the top play's own row using the anchor
convention **`{DASH_PUBLIC_URL}#play-<sid>`** — `sid` is the ledger id already stamped onto
each row by `ledger.log_surfaced`. T2 builds the matching anchor in the template; this row
only has to emit the URL in that exact form.

Also fix the digest URL: `main()` currently builds it from `DASH_URL` defaulting to
`http://localhost:9134/`. A localhost link in a phone notification is dead. Use
`url_or_dash()`, which already prefers the public URL.

Add a `--selftest` branch to `run.py`'s `__main__` that calls a `demo()` function in the
same style as `slips.py:demo()`. `demo()` must assert, on hand-built fake scored rows:
a 12% play appears in `digest_lines`, a 4% play does not, a `verify_in_app` 30% play
renders with the `unverified` marker, an empty result set produces zero lines, and the
built URL ends in `#play-` plus the top play's sid. It prints `run: all asserts pass`.

- **done-when:** `python run.py --selftest` prints `run: all asserts pass`, `_ntfy` has no
  unconditional early return, and no localhost URL is reachable from the digest path.
- **verify:**
  ```bash
  python run.py --selftest | grep -q "run: all asserts pass"
  grep -q "DIGEST_MIN_EV = 8.0" run.py
  ! sed -n '/def _ntfy(/,/^def /p' run.py | grep -qE '^\s+return\s*$'
  ! grep -n 'DASH_URL", "http://localhost' run.py
  ```


### T2 -- Give every board row a linkable anchor
- model: deepseek

The notification from T1 links to `https://ev.austinharger.com/#play-<sid>`. Nothing in
the board answers to that yet.

In `templates/index.html`, the row element at line 85 (`<tr data-app=... data-sport=...>`)
gains `id="play-{{ r.sid }}"`. `sid` is already on every row object — `run.py` sets
`r["sid"] = ledger.log_surfaced(r, ...)` before the snapshot is written. If a row somehow
lacks a sid, fall back to the loop index so the id is never `play-None`.

In `static/ev.js`, add a hash handler that runs on `DOMContentLoaded` **and** on
`hashchange`: if `location.hash` starts with `#play-`, find that element, clear any active
client-side filters that would hide it (the EV slider and the app/sport/state selects),
call `scrollIntoView({block: "center"})`, and add a `.pulse` class. Add a `.pulse` rule to
`static/ev.css` — a 2-second background highlight that then fades. The filter-clearing
matters: a linked play that lands behind an active min-EV filter looks to Austin like a
broken link.

Write `tools/render_check.py`: it imports `app`, uses Flask's test client to GET
`/?key=` + `app.SECRET`, and asserts the response contains `id="play-` and that no anchor
renders as `play-None`. It exits non-zero on failure and prints `render: ok` on success.

- **done-when:** `python run.py --fixture && python tools/render_check.py` prints
  `render: ok`, and `static/ev.js` handles `#play-` on both load and hashchange.
- **verify:**
  ```bash
  python run.py --fixture
  python tools/render_check.py | grep -q "render: ok"
  grep -q 'id="play-' templates/index.html
  grep -q 'hashchange' static/ev.js
  grep -q 'pulse' static/ev.css
  ```


### [x] T3 -- Real per-app state legality instead of the hardcoded "NC"
- model: glm
- depends-on: T1

`app.py:76` does `b.setdefault("states", "NC")`. Every row therefore claims to be legal in
NC and only NC, which makes the `f-state` select in the filter bar meaningless and would
let a push name a play Austin cannot enter.

`venues.py` already carries the truth in prose: each venue has a `states_note` such as
`"31 states + DC. Not NY NJ PA MI OH CT MD TN IA. CO CC banned Aug 12 2026 incl. indirect"`.
Convert that prose into structure **without deleting the notes** — the notes are
hand-verified and stay as the audit trail.

Add to each venue entry a `blocked_states` list of two-letter codes parsed from its own
`states_note` (a `Not XX YY ZZ` clause, plus any state named as banned). Where a note names
no exclusions, `blocked_states` is `[]`. Add `MY_STATE = os.environ.get("MY_STATE", "NC")`
to `venues.py` and a function `legal_in(app, state=None) -> bool` returning False when
`state` (defaulting to `MY_STATE`) is in that app's `blocked_states`, and True for an app
`venues.py` does not know about (unknown is not illegal — it is unverified).

In `app.py`, replace the hardcoded default with the venue answer: a row's `states` becomes
the app's legal-state summary, and a row that is **not** `legal_in` its app is still
rendered but tagged `NOT IN {MY_STATE}` and sorted below every legal row. Do not silently
drop it — a hidden row is indistinguishable from a bug.

In `run.py`, `digest_lines()` (T1 created it; it is already in the tree because this row
depends on T1) must skip plays that are not `legal_in` their app.
The board may show them; the phone must not.

Add a `demo()` to `venues.py` printing `venues: all asserts pass`, asserting: PrizePicks is
not legal in PA, is legal in NC, an unknown app returns True, and `MY_STATE` is honored
when passed explicitly.

- **done-when:** `python venues.py` prints `venues: all asserts pass` and `app.py` no
  longer contains a hardcoded `"NC"` default.
- **verify:**
  ```bash
  python venues.py | grep -q "venues: all asserts pass"
  ! grep -q 'setdefault("states", "NC")' app.py
  grep -q "def legal_in" venues.py
  python -c "import venues; assert not venues.legal_in('prizepicks','PA'); assert venues.legal_in('prizepicks','NC'); assert venues.legal_in('nosuchapp','PA'); print('gate ok')" | grep -q "gate ok"
  ```


### T4 -- Widen the live pull to fit the real quota, with a budget check that proves it
- model: deepseek

The quota is 20,000 credits/month and the live pull currently spends about 4,400 of it.
The 2026-08-19 grilling settled: widen.

An Odds API event-odds call costs `markets x regions` credits. `ingest.py` queries regions
`us,us_dfs` (and `us_ex` unless `SKIP_EX`), so read the region count from the code rather
than hardcoding a number.

Widen `SPORTS` to the markets the 8/19 backfill already proved fetchable:
`baseball_mlb: batter_total_bases, pitcher_strikeouts, batter_hits, batter_home_runs` and
`basketball_wnba: player_points, player_rebounds, player_assists`. Raise
`MAX_EVENTS_PER_SPORT` from 8 to 16.

Then add `budget_report() -> dict` to `ingest.py` and a `--budget` CLI flag that prints
exactly this line, computed from the live constants:

```
monthly_credits: <n>
```

The pull runs twice a day (the `EVDashboardPull` schtask), so monthly = per-pull x 2 x 31.
**Choose the widening so `monthly_credits` lands under 14,000** — the headroom is the
reserve for NFL/CFB history when that season starts. If the widening above overshoots,
lower `MAX_EVENTS_PER_SPORT` until it fits and say so in a comment naming the arithmetic.
Do not lower the market list; breadth of markets is what the DFS apps actually post.

- **done-when:** `python ingest.py --budget` prints a `monthly_credits:` line whose value
  is greater than 4,400 and less than 14,000.
- **verify:**
  ```bash
  python ingest.py --budget | grep -q "^monthly_credits: "
  python -c "import ingest; n=ingest.budget_report()['monthly_credits']; assert 4400 < n < 14000, n; print('budget ok')" | grep -q "budget ok"
  grep -q "MAX_EVENTS_PER_SPORT = 16" ingest.py
  grep -q "batter_home_runs" ingest.py
  ```


### [x] T5 -- clv.py: the tool that reads the 98,665 rows
- model: glm

98,665 `hist_lines` rows were bought to answer one question: **does a play this board would
have surfaced move toward its number by the close?** That is CLV, and it is the only proxy
available — prop *results* are not in the Odds API, so a settled-bet backtest cannot be
built at any price.

The 8/19 burn added the T-15m rung on purpose. Before it, every CLV number stopped an hour
short of close and was worthless.

Write `clv.py`. Schema facts you need and must not re-guess: the table is `hist_lines`, the
book column is named **`book`** (not `bookmaker`), and each row is one snapshot of one
selection. Snapshot rungs present are T-6h, T-3h, T-1h and T-15m.

`clv.py --db <path> --out diagnostics/clv_report.md`:

1. Join each `(event, market, selection)` at its T-6h snapshot to the same key at T-15m.
2. Devig each side pairwise (over/under normalization) and take the median fair price
   across books where at least `MIN_BOOKS`=3 quoted it — reuse `ingest.py`'s existing devig
   helpers by import rather than reimplementing them, so one devig model governs both.
3. For every T-6h selection whose devigged edge cleared +3%, record whether the T-15m
   consensus moved **toward** that selection (CLV positive) or away.
4. Write the report, which must contain these three lines verbatim in this format:

```
clv_pairs: <n>
clv_beats_close_pct: <n>
clv_mean_move_pct: <n>
```

`clv_beats_close_pct` is the share of +3% picks the close agreed with. Above 50% means the
board is finding real edge before the market does; at or below 50% means it is finding
noise, and that is a legitimate finding to report — do not tune the query until the number
looks good.

**The runner has no database.** Write `tools/make_clv_fixture.py`, which builds
`fixtures/clv_fixture.db` deterministically (no randomness — a fixed seeded list of rows in
the source), containing at least 40 selections across both rungs and both sports, with a
known-by-construction answer. `clv.py` must produce a report from it. State the expected
`clv_beats_close_pct` for the fixture in a comment in the fixture builder, and have the
verify assert `clv.py` reproduces it.

- **done-when:** `python clv.py --db fixtures/clv_fixture.db --out diagnostics/clv_report.md`
  writes a report containing all three required lines, and `clv_beats_close_pct` matches the
  fixture's constructed value.
- **verify:**
  ```bash
  python tools/make_clv_fixture.py
  python clv.py --db fixtures/clv_fixture.db --out diagnostics/clv_report.md
  grep -qE "^clv_pairs: [0-9]+$" diagnostics/clv_report.md
  grep -qE "^clv_beats_close_pct: [0-9.]+$" diagnostics/clv_report.md
  grep -qE "^clv_mean_move_pct: -?[0-9.]+$" diagnostics/clv_report.md
  python tools/make_clv_fixture.py --assert-report diagnostics/clv_report.md
  ```


### T6 -- The box handoff, written down
- model: deepseek
- depends-on: everything

Nothing above reaches Austin's phone until the code reaches the Windows box and the tunnel
is up. loop-ci defect 4 (2026-08-19) was exactly this: a run went green on Actions and the
commit never landed on the machine that runs it.

Write `diagnostics/deploy_0.6.md` — a checklist, in order, each step with the literal
command and what proves it worked. It must name, at minimum:

1. `git pull` in `C:\Users\aharg\ev-dashboard` and confirm HEAD matches this run's merge
   commit. **This is the step defect 4 skipped.**
2. Export a persistent `SECRET` in the box environment before starting `app.py` — an unset
   `SECRET` mints a fresh random key every boot, which silently invalidates the link in
   every notification already sent.
3. `pm2 start` the dashboard on `:9134` and confirm the port listens (`pm2 list` currently
   shows only `omniroute` and `bgutil-pot`; `:9134` is silent).
4. Bring the Cloudflare Zero Trust tunnel up and confirm `https://ev.austinharger.com`
   resolves to the board.
5. Subscribe the phone to ntfy topic `aharg-ev` and fire one test push.
6. Run `python clv.py --db ev_ledger.db --out diagnostics/clv_report.md` against the **real**
   98,665-row database and paste the three result lines into `Projects/ev-dashboard.md`.
   This is the number that decides whether the Odds API plan is worth re-buying — a
   question deliberately left open on 8/19 because "do not cancel a plan whose only real
   test has not been run."
7. `git add backfill.py close_burn.py` — both are untracked on the box and both are the
   tools that spent 20,000 credits. They are not in this repo and this run cannot add them.

Each step is a `- [ ]` line so it can be worked through on a phone.

- **done-when:** `diagnostics/deploy_0.6.md` exists and names all seven steps as unchecked
  checkbox lines, including the real-DB clv run and the untracked-file commit.
- **verify:**
  ```bash
  test -s diagnostics/deploy_0.6.md
  test "$(grep -c '^- \[ \]' diagnostics/deploy_0.6.md)" -ge 7
  grep -q "ev.austinharger.com" diagnostics/deploy_0.6.md
  grep -q "close_burn.py" diagnostics/deploy_0.6.md
  grep -q "SECRET" diagnostics/deploy_0.6.md
  ```

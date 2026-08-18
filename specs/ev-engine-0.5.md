# EV-ENGINE 0.5 - Minimal working dashboard, one-click slips, direct DFS feeds

status: ready
version: ev-engine-0.5
repo: aharger3/ev-dashboard
doc: Projects/ev-engine.md

target: bring ev.austinharger.com back to life as an OddsJam-style dark board that shows real +EV slips from every CC-fundable pick'em app, each with a one-click Go button that opens the app and copies the legs, plus a manufactured-spend venue board for the apps that have no odds feed.

Context the runner needs, because none of it is in the repo:

- The pipeline has produced **zero rows since 2026-07-28**. `latest.json` today reads
  `{"ts": ..., "credits": null, "rows": []}`. `credits: null` means the Odds API
  quota header was never read — the request is probably erroring and being swallowed
  into exit 0. That silent-success bug is the reason this whole version exists.
- Existing modules: `ingest.py` (Odds API pull + devig), `slips.py` (slip builder),
  `ev_engine.py` (EV/Kelly/score), `ledger.py` (SQLite), `run.py` (orchestrator),
  `app.py` (Flask, only `GET /` and `POST /placed`), `true_ev.py` (retired Underdog path).
- Settled decisions, do not re-litigate: state = **NC**. Bankroll **$2,500**.
  EV floor **+3%**. No auto-placement, ever — the human taps. No sportsbooks.
- Offline fixtures live in `fixtures/`. **Every `verify:` below must pass with no
  network and no API key**, because the Actions runner has neither.

---

### T1 -- Direct PrizePicks + Underdog line feeds

- model: glm

The Odds API's own docs say DFS-region odds are *"indicative only."* That is why
PrizePicks and Underdog surface 0 slips while Dabble surfaces 100% of them. Both apps
serve public unauthenticated JSON with their **exact posted lines**, free, costing zero
Odds API credits.

Create `dfs_direct.py` with:

- `fetch_prizepicks() -> list[dict]` hitting PrizePicks' public projections endpoint
  (`https://api.prizepicks.com/projections`, JSON:API format — `data[]` are projections,
  `included[]` carries the `new_player` records; join on
  `data[i].relationships.new_player.data.id`). Normalize to
  `{app, player, team, league, stat_type, line, odds_type, start_time}`.
  `odds_type` must preserve `standard` / `goblin` / `demon`.
- `fetch_underdog() -> list[dict]` hitting Underdog's public over/under lines endpoint
  (`https://api.underdogfantasy.com/beta/v5/over_under_lines`), normalized to the same
  shape. Underdog nests the stat under `over_under.appearance_stat`.
- `normalize(raw, app) -> list[dict]` — the one shared shaping function both use.
- A `demo()` that runs against `fixtures/prizepicks_projections.json` and
  `fixtures/underdog_lines.json`, which you must also create by hand as small (3-5
  record) but **structurally faithful** samples of each API's real response shape.
- Network calls must go through a `_get(url)` helper with a 10s timeout that **raises**
  on a non-200. Never return `[]` on an error — that is the exact bug this version is
  fixing.

Then wire it in: `run.py` merges `dfs_direct` rows into the app-line pool that
`slips.app_picks()` consumes, so PrizePicks/Underdog legs are priced against the
Odds API devigged consensus but use the app's real line. Odds API stays the source of
**fair probability**; the direct feeds are the source of **the line you can actually tap**.

- **done-when:** `python dfs_direct.py` runs offline against both fixtures and prints
  normalized rows for both apps; a non-200 raises instead of returning empty.
- **verify:**
  ```bash
  test -f fixtures/prizepicks_projections.json
  test -f fixtures/underdog_lines.json
  python dfs_direct.py
  python -c "import dfs_direct,json; r=dfs_direct.normalize(json.load(open('fixtures/underdog_lines.json')),'underdog'); assert len(r)>0; assert set(['app','player','stat_type','line']) <= set(r[0]), r[0]"
  python -c "import dfs_direct,inspect; s=inspect.getsource(dfs_direct._get); assert 'raise' in s and 'timeout' in s, 'error path must raise'"
  grep -q "dfs_direct" run.py
  ```

---

### T2 -- Kill the silent-success bug

- model: glm

`run.py` exits 0 and writes `rows: []` when the pull fails. Every layer reports success
on exit code and nothing asserts on output. Fix it at the source.

In `run.py`:

- Read and store the Odds API quota headers (`x-requests-remaining`,
  `x-requests-used`) into the snapshot's `credits` field. If they are absent, that is a
  **failed request** — raise, do not write `null`.
- Add `assert_snapshot(snap)` which raises `SnapshotEmpty` when `rows` is empty **and**
  the slate was non-empty, and raises `SnapshotStale` when `credits` is `None`.
- `run.py` must exit **non-zero** on either. A silent empty pull must break the job.
- Add `--allow-empty` for genuine no-slate days (off-season, no games), so the failure
  mode stays honest instead of being suppressed by default.
- Write every exception, with traceback, to `logs/pull.log` before re-raising.

Also write `diagnostics/pull_report.md` explaining, from reading the code alone, the
exact chain by which a failed Odds API request became `credits: null, rows: []` and
`exit 0`. Include a line in this literal format so it is greppable:

`root_cause: <one sentence>`

- **done-when:** an empty snapshot exits non-zero without `--allow-empty`, `credits`
  is never silently `None`, and `diagnostics/pull_report.md` names the root cause.
- **verify:**
  ```bash
  grep -q "^root_cause: " diagnostics/pull_report.md
  python -c "import run; run.assert_snapshot({'credits':1000,'rows':[{'a':1}]})"
  ! python -c "import run; run.assert_snapshot({'credits':None,'rows':[{'a':1}]})"
  ! python -c "import run; run.assert_snapshot({'credits':1000,'rows':[]})"
  grep -q "allow-empty" run.py
  ```

---

### T3 -- OddsJam-style dark board

- model: glm

Build `templates/index.html` + `static/ev.css` + `static/ev.js`. Dense dark table,
OddsJam as the visual reference. No CDN, no build step, no framework — plain HTML/CSS/JS
served by Flask.

- Sticky header row. One row per slip: app chip, legs (player · stat · line · O/U),
  payout multiplier, EV%, Kelly stake, Go button.
- EV% color-ramped: `+3-8%` dim green, `+8-15%` bright green, `+15-25%` amber,
  `>25%` red with a `VERIFY IN APP` tag (see T7).
- Filter bar, all client-side against the rendered rows: sport, app, min-EV slider,
  and a **state toggle defaulting to NC** (T6 supplies the data attribute).
- Readable on a phone in portrait — the table must scroll horizontally inside its own
  container, never make the page body scroll sideways.
- A header strip showing `credits remaining`, `last pull` timestamp, and slip count.
  When the last pull failed, that strip turns red and says so. The dashboard being
  wrong must be visible from across the room.
- Every row carries `data-app`, `data-sport`, `data-ev`, `data-states` attributes —
  the filters read those, not the text.

- **done-when:** `python -c "import app"` imports clean and the template renders a table
  with the filter bar, the credits strip, and per-row data attributes.
- **verify:**
  ```bash
  test -f templates/index.html && test -f static/ev.css && test -f static/ev.js
  grep -q "data-ev" templates/index.html
  grep -q "data-states" templates/index.html
  grep -qi "credits" templates/index.html
  ! grep -qE "src=\"https?://|cdn\." templates/index.html
  python -c "from jinja2 import Environment, FileSystemLoader as F; h=Environment(loader=F('templates')).get_template('index.html').render(rows=[], venues=[], credits=1234, last_pull='x', ok=True); assert '<table' in h and 'filter' in h.lower(), h[:400]"
  ```

---

### T4 -- One-click Go: deep link + clipboard

- model: glm

No pick'em app publishes an add-to-slip URL. What ships in 0.5 is: **one button that
opens the right app to the right board AND copies the legs to the clipboard**, so Austin
pastes into the app's search, taps the legs, picks a stake, and submits.

Create `deeplinks.py`:

- `APP_LINKS: dict[str, dict]` — per app, a `web` URL and an optional `scheme` URL
  (custom scheme for the installed mobile app), plus a `deposit` URL for T5's venue
  board. Cover: `dabble_us_dfs`, `prizepicks`, `underdog`, `pick6`, `boom`, `sleeper`,
  `parlayplay`, `chalkboard`, `splash`, `prophetx`.
- `go_url(app, sport=None) -> str` — deepest URL known for that app and sport, falling
  back to the app's board root. Unknown app raises `KeyError`; never return `None` or
  an empty string into an `href`.
- `slip_text(slip) -> str` — the copy payload, one leg per line:
  `Mahomes | pass yds | O 249.5` — plus a final line `EV +7.2% | stake $18`.

In `static/ev.js`, the Go button does both in one tap: `navigator.clipboard.writeText`
then `window.open`. Clipboard failures (no HTTPS, denied permission) must fall back to
showing the text in a selectable box — the button must never do nothing.

- **done-when:** every app in `APP_LINKS` returns a non-empty `go_url`, `slip_text`
  formats legs one per line, and the button degrades gracefully without clipboard access.
- **verify:**
  ```bash
  python -c "import deeplinks as d; need={'dabble_us_dfs','prizepicks','underdog','pick6','boom','sleeper','parlayplay','chalkboard','splash','prophetx'}; assert need <= set(d.APP_LINKS), need - set(d.APP_LINKS); assert all(d.go_url(a).startswith('http') for a in need); assert all(d.APP_LINKS[a].get('deposit') for a in need)"
  ! python -c "import deeplinks as d; d.go_url('nope')"
  python -c "import deeplinks as d; t=d.slip_text({'app':'prizepicks','ev_pct':7.2,'stake':18,'legs':[{'player':'Mahomes','stat_type':'pass yds','side':'O','line':249.5}]}); assert 'Mahomes' in t and '249.5' in t and 'EV' in t, t"
  grep -q "clipboard" static/ev.js
  grep -qi "catch" static/ev.js
  ```

---

### T5 -- Manufactured-spend venue board

- model: deepseek

Six CC-fundable apps have no odds feed at all — Boom, Sleeper, ParlayPlay, Chalkboard,
Splash, ProphetX. They still matter, because the deposit is the points play. Give them a
second section on the dashboard: a venue card each, no lines.

Create `venues.py` with `VENUES: list[dict]`, one entry per app, each carrying
`app, cc_accepted, cards, limit, states_note, cash_advance_verified, warning, deposit_url`.
Transcribe **exactly** these, they are hand-verified 2026-08-09 and must not be invented:

| app | cc | cards | limit | note |
|---|---|---|---|---|
| dabble_us_dfs | yes | Visa, MC credit+debit, Apple/Google Pay, PayPal | $5 min, max 2 cards | 31 states + DC. Not NY NJ PA MI OH CT MD TN IA. CO CC banned Aug 12 2026 incl. indirect |
| prizepicks | yes | Visa, MC, Amex, Discover | $10 min | Player Picks only. CC deposit-only. Silent limiting ~200 entries |
| underdog | yes | Visa, MC, Discover, Amex, PayPal, Trustly | $10 min, max 7 cards | Prepaid/gift rejected. CO CC banned Aug 12 2026 |
| pick6 | yes | Visa, MC, PayPal, Venmo, Play+, Trustly | $5 min | DFS exempted from the Aug 2025 DK ban. Cash-advance coding UNVERIFIED |
| boom | yes | Visa, MC, Discover, Amex, PayPal, Venmo | $10 min | Amex confirmed 2026-08-01 |
| sleeper | yes | Visa, Discover only | $1,000/day | No Mastercard |
| parlayplay | yes | Visa, MC, Discover | $1,000/day | No app-side fees |
| chalkboard | yes | Visa, MC, Discover, PayPal/Venmo bank-linked only | $5,000/day | App warns issuer may code as cash advance |
| splash | yes | Visa, MC, Discover, PayPal, Venmo, ACH | — | Some issuers code as cash advance. 40+ states incl. NY |
| prophetx | yes | Visa, MC via PayNearMe | $5,000/txn | CFTC-regulated, 49 states, not NV. Cash-advance coding UNVERIFIED |

`cash_advance_verified` is `False` for every row — nobody has checked a statement. Any
row where it is `False` renders with a ⚠️ and the text `CA CODING UNVERIFIED — $10 test
first`. Also add `betr` with `cc_accepted: False` so it is visibly excluded rather than
silently missing. Render the section from `templates/index.html` via a `venues` variable.

- **done-when:** all 11 apps present, every `cash_advance_verified` is False, and the
  template renders the venue section.
- **verify:**
  ```bash
  python -c "import venues; by={v['app']:v for v in venues.VENUES}; need={'dabble_us_dfs','prizepicks','underdog','pick6','boom','sleeper','parlayplay','chalkboard','splash','prophetx','betr'}; assert need <= set(by), need-set(by); assert by['betr']['cc_accepted'] is False; assert by['sleeper']['cc_accepted'] is True; assert all(v['cash_advance_verified'] is False for v in venues.VENUES); assert all(v.get('deposit_url') for v in venues.VENUES if v['cc_accepted']); assert 'MC' not in by['sleeper']['cards']"
  grep -q "venues" templates/index.html
  ```

---

### T6 -- State placeability filter

- model: deepseek

18 of 18 slips in the last real snapshot came from one app, and nothing in the code
checks whether Austin can legally enter it from where he is. A ~15-line fix that would
have caught this on day one.

Add `APP_STATES: dict[str, set[str]]` to `slips.py` and a `MY_STATE` env var defaulting
to `NC`. `placeable(app, state) -> bool`. `build_slips()` tags each slip with
`states` and `placeable_here`; `run.py` keeps unplaceable slips in the snapshot but
flags them, so they render greyed rather than vanishing (a hidden slip teaches nothing).

Dabble's exclusions are load-bearing and exact: **not** NY, NJ, PA, MI, OH, CT, MD, TN, IA
— and CO's credit-card path closed Aug 12 2026. PA matters specifically: NC is home, PA is
where he has been physically.

- **done-when:** `placeable('dabble_us_dfs','PA')` is False, `('dabble_us_dfs','NC')` is
  True, and slips carry `placeable_here`.
- **verify:**
  ```bash
  python -c "import slips; assert slips.placeable('dabble_us_dfs','NC') is True; bad=[s for s in ('PA','NY','NJ','MI','OH','CT','MD','TN','IA') if slips.placeable('dabble_us_dfs',s)]; assert not bad, bad"
  grep -q "MY_STATE" slips.py
  grep -q "placeable_here" run.py
  ```

---

### T7 -- EV guardrails: implausible-EV band, Kelly clamp, secret

- model: opus

Three small changes, each one a place where wrong math silently costs real money.

1. **`MAX_PLAUSIBLE_EV = 25.0` in `ev_engine.py`.** A slip above it is not deleted — it
   gets `verify_in_app = True` and renders in the red band. The Odds API says DFS odds are
   *"indicative only,"* and for a product-payout app like Dabble that error compounds
   across legs. A +37.9% slip is a stale-line smell, not a jackpot.
2. **Fix the backwards stake clamp.** `score()` clamps stake to `[5, 100]` *after* Kelly,
   so when ¼-Kelly says $2 the clamp *raises* the bet to $5 — the one direction a Kelly
   clamp must never move. Change it: when Kelly stake < `min_stake`, **drop the slip**
   (`below_min_stake`) instead of rounding up. Keep the $100 ceiling.
3. **`SECRET` must come from the environment**, default to a random token, and never be
   the literal `letmein`. The key currently rides in the querystring, so it leaks through
   referrer headers and browser history — also accept it from an `X-EV-Key` header and
   set the cookie `HttpOnly` + `SameSite=Lax`.

Do not change the `/ max(legs,1)` Kelly divisor. It is a deliberate safety margin and
changing it silently would resize every bet.

- **done-when:** a >25% slip is flagged not dropped, a sub-minimum Kelly stake drops the
  slip instead of rounding up, and `letmein` appears nowhere in the tree.
- **verify:**
  ```bash
  ! grep -rn "letmein" --include=*.py .
  python -c "import ev_engine as e, inspect; assert e.MAX_PLAUSIBLE_EV == 25.0; src=inspect.getsource(e.score); assert 'verify_in_app' in src, 'high-EV slips must be flagged'; assert 'below_min_stake' in src, 'sub-min Kelly must drop, not round up'; assert 'max(legs' in src or 'max(l' in src, 'Kelly divisor must be untouched'"
  python -c "import app; s=getattr(app,'SECRET',None); assert s and s != 'letmein', s"
  grep -qi "httponly" app.py
  ```

---

### T8 -- Slate-day 5-minute poller

- model: deepseek

20,000 Odds API credits to spend in roughly one day, and the note identifies the real
edge as PrizePicks lagging the market by 15-30 minutes during peak windows — which a
twice-daily cron cannot possibly harvest.

Create `poll.py`: a foreground loop that runs `run.py`'s pull every **5 minutes**, today's
slate only, and stops on any of — credits below a `RESERVE = 2000` floor, a
`--until HH:MM` wall-clock limit, or `Ctrl-C`. Each cycle appends one line to
`logs/poll.log` in this literal format so the burn is greppable afterwards:

`poll ts=<iso8601> credits_left=<int> rows=<int> new=<int>`

`new` = slips not present in the previous cycle's snapshot. Direct PrizePicks/Underdog
feeds from T1 are free — poll those every cycle regardless of the credit floor.

**Do not add a cron, schtask, or scheduled task.** This is a script Austin starts by hand
on a slate day and Ctrl-C's when he's done. `--dry-run` must exercise the full loop
against fixtures with zero network calls, so the runner can verify it.

- **done-when:** `python poll.py --dry-run --cycles 3` writes 3 correctly-formatted lines
  and never calls the network.
- **verify:**
  ```bash
  rm -f logs/poll.log
  python poll.py --dry-run --cycles 3
  test "$(grep -c '^poll ts=' logs/poll.log)" = "3"
  grep -qE '^poll ts=[0-9T:+-]+ credits_left=[0-9]+ rows=[0-9]+ new=[0-9]+$' logs/poll.log
  python -c "import poll, inspect; s=inspect.getsource(poll); assert 'RESERVE' in s and '2000' in s; assert 'schtask' not in s.lower() and 'crontab' not in s.lower()"
  ```

---

### T9 -- Wire it together and write the deploy note

- model: glm
- depends-on: everything

Make `app.py` actually serve the thing. Routes:

- `GET /` — the T3 board: placeable slips first, unplaceable greyed, venue board below.
- `POST /placed` — unchanged, still writes the ledger.
- `GET /healthz` — returns 200 plus `{last_pull, credits, rows, ok}`. `ok` is **false**
  when the last pull failed or the snapshot is older than 6 hours. This is the endpoint
  that would have caught the 7/28 outage on the day it happened.

Then write `DEPLOY.md`, the runbook for the Windows box — it is the only artifact Austin
touches by hand. It must cover, in order: `git pull` in `C:\Users\aharg\ev-dashboard`,
the env vars to set (`ODDS_API_KEY`, `SECRET`, `MY_STATE=NC`), `pm2 restart ev-dashboard`,
confirming `:9134` listens, re-checking the Cloudflare tunnel for `ev.austinharger.com`
(down since 7/28), killing the superseded `ev-bot` on `:9132` and its auto-start task, and
starting `poll.py` by hand on a slate day. Include a `## Verify` section with the literal
commands to paste.

Finally append a `## 0.5 shipped` section to the run summary listing every module added
and what still is not done — specifically that no app has had a $10 cash-advance test and
that one-click is deep-link-plus-clipboard, not a true add-to-slip API.

- **done-when:** `/healthz` reports `ok:false` on a stale snapshot, `DEPLOY.md` covers
  every step above, and the whole app imports clean.
- **verify:**
  ```bash
  python -c "import app, run, slips, ev_engine, ledger, deeplinks, venues, dfs_direct, poll"
  python -c "import app; r=app.app.test_client().get('/healthz'); assert r.status_code == 200, r.status_code; j=r.get_json(); assert set(['last_pull','credits','rows','ok']) <= set(j), j"
  for s in 'git pull' 'pm2' '9134' 'ev.austinharger.com' 'ODDS_API_KEY' 'MY_STATE' '9132' 'poll.py'; do
    grep -q "$s" DEPLOY.md || { echo "DEPLOY.md missing: $s"; exit 1; }
  done
  grep -q "^## Verify" DEPLOY.md
  ```

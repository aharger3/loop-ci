// loop-watchdog - the watchdog's watchdog. Runs on Cloudflare, NOT on GitHub.
//
// Why it cannot live in loop.yml: the `alarm` job exists to page when the loop never starts,
// but it needs a hosted runner like every other job. 2026-08-06 run 31119619358 - GitHub
// could not allocate a runner, `plan` queued 15 min and was cancelled with zero steps, and
// `alarm` queued 15 min and was cancelled with zero steps. Austin pushed a spec and his phone
// stayed silent, which is indistinguishable from "nothing was pending". Anything inside
// Actions that reports on runner starvation is subject to runner starvation.
//
// THE RULE: `alarm` completing with conclusion `success` is the loop's proof-of-life.
// It is `if: always()` with no `needs` gate, so on a healthy run it runs, evaluates its
// condition to false, skips its step and finishes green. Anything else - cancelled, failed,
// or absent - means nothing in that run could be trusted to have sent a notification.
//
// Verified against real history 2026-08-07:
//   31122686346  run=cancelled  alarm=success   -> quiet  (report had already sent `done`)
//   31119619358  run=failure    alarm=cancelled -> page   (the actually-silent run)
// Note the first line: the RUN's own conclusion is a bad signal - it was `cancelled` on a
// clean 16-row run because a doc-refresh step timed out. Do not switch this to run.conclusion.
//
// Deliberately not a fifth notification type: it posts `blocked`, same as every other
// "this needs you" page, so the channel still has exactly four.

const REPO = 'aharger3/loop-ci';
const WORKFLOW = 'loop.yml';          // price-watch.yml is not watched - it pages nobody
const TOPIC = 'aharg-loop';
const WINDOW_MIN = 25;                // > the 20-min cron on purpose, see check()

export default {
  async scheduled(event, env, ctx) {
    // One line per tick, always, even on a quiet one - `wrangler tail` and the Workers
    // observability panel are the only place this thing is visible, and Austin's own rule is
    // that the ABSENCE of a per-run line is the alarm. A watchdog with no heartbeat has the
    // same failure mode as the thing it watches.
    ctx.waitUntil(
      check(env, false)
        .then(v => console.log(`[watchdog] ${v.replace(/\n/g, ' | ')}`))
        .catch(e => console.error(`[watchdog] FAILED: ${e.message}`)));
  },
  // GET the worker URL for a DRY RUN: same query, same verdict, sends nothing. Safe to expose
  // and safe to curl - a watchdog whose test button pages the phone does not get tested.
  async fetch(request, env) {
    return new Response(await check(env, true), { headers: { 'content-type': 'text/plain' } });
  },
};

// env.fetch is an injection point for check.test.js and nothing else. In production env comes
// from the Cloudflare runtime and has no `fetch` key, so this is the global one. The test can
// then replay recorded GitHub responses through the REAL check(), with no token and no network.
async function gh(env, path) {
  const r = await (env.fetch || fetch)(`https://api.github.com${path}`, {
    headers: {
      Authorization: `Bearer ${env.GH_TOKEN}`,
      Accept: 'application/vnd.github+json',
      'User-Agent': 'loop-watchdog',      // GitHub 403s a request with no UA
    },
  });
  if (!r.ok) throw new Error(`GitHub ${r.status} ${path}: ${(await r.text()).slice(0, 200)}`);
  return r.json();
}

// windowMin is a parameter only so check.test.js can replay real history through the exact
// code that runs in production instead of a copy of it. Nothing else passes it.
export async function check(env, dry, windowMin = WINDOW_MIN) {
  // The window OVERLAPS the cron interval (25 min window, 20 min tick) so a single failed
  // tick - a GitHub 5xx, a Cloudflare hiccup - cannot drop the one page that matters. The
  // cost is that a genuinely silent run can page twice. That trade is deliberate: this fires
  // only on real infrastructure silence, which is rare, and a duplicate alarm is annoying
  // while a missed one is the entire bug being fixed here.
  // ponytail: stateless on purpose. If duplicates ever become the complaint, put the last
  // paged run id in a KV namespace and skip it - do not shrink the window.
  const cutoff = Date.now() - windowMin * 60_000;

  const { workflow_runs } = await gh(
    env, `/repos/${REPO}/actions/workflows/${WORKFLOW}/runs?status=completed&per_page=20`);
  const fresh = workflow_runs.filter(r => Date.parse(r.updated_at) >= cutoff);

  const silent = [];
  for (const run of fresh) {
    const { jobs } = await gh(env, `/repos/${REPO}/actions/runs/${run.id}/jobs`);
    const alarm = jobs.find(j => j.name === 'alarm');
    if (alarm && alarm.conclusion === 'success') continue;
    silent.push({
      id: run.id,
      url: run.html_url,
      title: (run.display_title || '').slice(0, 60),
      run: run.conclusion,
      alarm: alarm ? alarm.conclusion : 'job never ran',
      // Zero steps on a cancelled job is the fingerprint of "no runner was ever allocated",
      // as opposed to a job that ran and broke. Worth saying out loud in the page, because
      // the two need completely different responses from Austin.
      starved: !!alarm && alarm.conclusion === 'cancelled' && (alarm.steps || []).length === 0,
    });
  }

  const verdict = `${fresh.length} completed run(s) in the last ${windowMin} min, ` +
                  `${silent.length} silent.\n` +
                  silent.map(s => `  ${s.id} run=${s.run} alarm=${s.alarm}`).join('\n');
  if (!silent.length || dry) return (dry ? '[DRY RUN, nothing sent]\n' : '') + verdict;

  const body = [
    `${silent.length} loop run(s) finished without being able to notify you.`,
    '',
    ...silent.map(s => `- ${s.title || s.id}: run ${s.run}, alarm ${s.alarm}` +
      (s.starved ? '\n  GitHub never allocated a runner. Nothing was spent and no spec row ran.'
                 : '\n  The notification path itself broke - open the run and read the alarm job.')),
    '',
    'To retry: re-run the failed jobs on the run page, or trigger The Loop from the Actions tab.',
    'If this repeats, check Actions minutes at github.com/settings/billing - loop-ci is private,',
    'so runners are metered, and an exhausted balance looks exactly like this.',
  ].join('\n');

  await fetch(`https://ntfy.sh/${TOPIC}`, {
    method: 'POST',
    headers: {
      Title: 'Loop went silent',
      Priority: 'high',
      Tags: 'warning',
      Actions: `view, Open run, ${silent[0].url}`,
    },
    body,
  });
  return verdict;
}

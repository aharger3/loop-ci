// node watchdog/check.test.js   (no token, no network)
//
// Replays the two 2026-08-06 runs through the SAME check() the cron runs, dry, and asserts they
// land on opposite verdicts. The whole watchdog is one boolean - if that boolean inverts, this
// is the thing that says so.
//
// It used to call the live GitHub API with GH_TOKEN=$(gh auth token), which meant it could not
// run in CI and would start failing on its own the day those two runs aged out of Actions
// retention. The responses are recorded in fixture.json now and injected through env.fetch.
import assert from 'node:assert';
import { readFileSync } from 'node:fs';
import { check } from './worker.js';

const fx = JSON.parse(readFileSync(new URL('./fixture.json', import.meta.url)));

// Stand-in for GitHub. Serves the run list and the per-run job list, and refuses anything else
// loudly - a check() that starts asking for a URL this does not know about is a change the test
// should notice rather than silently answer with an empty object.
function fakeFetch(runs) {
  return async (url) => {
    const path = String(url).replace('https://api.github.com', '');
    let body;
    if (path.includes('/actions/workflows/')) {
      body = { workflow_runs: runs };
    } else {
      const id = path.match(/\/actions\/runs\/(\d+)\/jobs/)?.[1];
      assert(id && fx.jobs[id], `test fixture has no answer for ${path}`);
      body = { jobs: fx.jobs[id] };
    }
    return { ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) };
  };
}

// Every fixture run is inside the window; check() filters on updated_at, so the window has to
// be wide enough to cover dates that recede further into the past every day this repo lives.
const WINDOW = 60 * 24 * 365 * 50;
const run = (runs) => check({ GH_TOKEN: 'fake', fetch: fakeFetch(runs) }, true, WINDOW);

// --- both runs together: exactly the discrimination the watchdog is for ---------------------
const out = await run(fx.runs);
console.log(out);
assert(out.includes('31119619358'), 'MISSED the silent run - the watchdog is not watching');
assert(!out.includes('31122686346'), 'FALSE PAGE on a run that already notified');
assert(out.includes('1 silent'), `expected exactly 1 silent, got: ${out}`);

// --- each one alone, so a pass cannot come from the two cancelling out -----------------------
const silentOnly = await run([fx.runs[0]]);
assert(silentOnly.includes('1 silent'), `silent run alone should page: ${silentOnly}`);
const notifiedOnly = await run([fx.runs[1]]);
assert(notifiedOnly.includes('0 silent'), `notified run alone should be quiet: ${notifiedOnly}`);

// --- a run with no alarm job at all is silent too --------------------------------------------
// `alarm` is skipped whenever plan succeeded, and a skipped job is absent from the jobs list in
// some API responses. That must count as silent, not as "fine".
fx.jobs['999'] = [{ name: 'plan', conclusion: 'success', steps: [] }];
const noAlarm = await run([{ ...fx.runs[0], id: 999 }]);
assert(noAlarm.includes('alarm=job never ran'), `a missing alarm job must read as silent: ${noAlarm}`);

// --- dry means dry ---------------------------------------------------------------------------
assert(out.startsWith('[DRY RUN'), 'dry run did not announce itself - it may have sent a page');

console.log('\nok: pages the silent run, stays quiet on the noisy-but-notified one');

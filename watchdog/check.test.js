// node watchdog/check.test.js   (needs: GH_TOKEN=$(gh auth token))
//
// Replays real loop-ci history through the SAME check() the cron runs, dry, and asserts the
// two runs that matter land on opposite verdicts. The whole watchdog is one boolean - if that
// boolean inverts, this is the thing that says so.
import assert from 'node:assert';
import { check } from './worker.js';

const env = { GH_TOKEN: process.env.GH_TOKEN };
assert(env.GH_TOKEN, 'set GH_TOKEN=$(gh auth token)');

// A window wide enough to include the 2026-08-06 runs. Dry: sends nothing.
const out = await check(env, true, 60 * 24 * 365);
console.log(out);

// 31119619358: no runner, alarm cancelled with zero steps, phone stayed silent -> must page.
assert(out.includes('31119619358'), 'MISSED the silent run - the watchdog is not watching');

// 31122686346: run conclusion `cancelled`, but alarm succeeded because report already sent
// `done` for 16 finished rows. Paging here would be the false alarm this replaces.
assert(!out.includes('31122686346'), 'FALSE PAGE on a run that already notified');

console.log('\nok: pages the silent run, stays quiet on the noisy-but-notified one');

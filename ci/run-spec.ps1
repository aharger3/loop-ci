# run-spec.ps1 - execute one parsed spec's tasks, in dependency order, on a CI runner.
#
# This replaces run-spec.js (36k, a Claude Code Workflow) and everything that propped it up.
# It is small because GitHub Actions already owns the hard parts:
#   .run.lock pid lock      -> concurrency: group
#   loop-guard.ps1 watchdog -> timeout-minutes
#   queue\NIGHT.md serial   -> one job per spec, running in parallel
#   logs\nightly.log        -> the run log
#   runDirect/child_process -> there is no Workflow sandbox here; we just run the CLI
#
# ============================================================================================
# 2026-08-09 - THE RULE THAT CHANGED: the runner confirms rows, models do not confirm themselves.
#
# For a week a row was "done" because the model wrote {"done": true} into a sentinel file, and
# NOTHING ever ran the check. Every failure mode of that design showed up in production:
#   omen-3.7  reported 0/9 while its PR carried 40 changed files.
#   omen-3.6, corpus-1.0, 3.7  returned done=true exactly zero times in 16 attempts.
#   omen-3.8 run 31318238961   reported 0/2 while T0 had written both of its artifacts, and the
#                              agent doing the work diagnosed it itself: "run-spec.ps1 has no
#                              independent done-when checker."
# Each round patched the handshake (strict boolean parse, 3 re-reads, stdout fallback, raw-byte
# dumps). The handshake was never the bug. Asking an LLM whether it succeeded is the bug.
#
# So: every row now carries `verify:` - a literal shell command. This script runs it in the
# target repo and the EXIT CODE is the row's state. The model's own claim is not read at all.
# What the model writes is commentary: a resultLine, plus questions/ideas/tasks for Austin.
# ============================================================================================
#
# Model routing is three env blocks over ONE binary. Anthropic native for opus; OpenRouter's
# Anthropic-compatible endpoint for glm and deepseek, both with an explicit provider pin.

param(
  [Parameter(Mandatory=$true)][string]$Parsed,      # spec-parsed.json from parse-spec.ps1
  [Parameter(Mandatory=$true)][string]$WorkDir,     # checkout of the spec's repo: target
  [int]$TaskTimeoutMin   = 25,
  [int]$VerifyTimeoutMin = 10,
  [int]$Attempts         = 3,
  # Wall-clock ceiling for the WHOLE spec, under the run job's timeout-minutes: 330. With 3
  # attempts a single row can now cost 75 min, so a 6-row spec's worst case (450 min) exceeds
  # the job timeout - and a job timeout kills the process, which used to mean every confirmed
  # row was lost with it. Past this budget the remaining rows are recorded as skipped and the
  # result file is written normally. A partial result that Austin can read beats a red X.
  [int]$BudgetMin        = 300,
  [string]$Out = 'result.json',
  [switch]$DryRun          # print tier + order + ETA and spend nothing. The old -WhatIf.
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'result-parse.ps1')
$plan = Get-Content $Parsed -Raw -Encoding UTF8 | ConvertFrom-Json
$runStart = Get-Date

# Snapshot every secret ONCE, before the task loop touches the process environment.
#
# 2026-08-06: the loop below clears $env:ANTHROPIC_API_KEY at the top of every task so a
# leftover value can't authenticate the next one. It then read the tier's secret back OUT of
# the same process environment - so the first glm row erased the key and every later opus row
# saw nothing and reported BLOCKED "add repo secret ANTHROPIC_API_KEY". The secret was there
# the whole time. This ate omen-3.4's T9 and omen-3.5's T5, and both runs told Austin to go
# add a secret that was already set. Read from this table, never from $env:, after this line.
$SECRETS = @{}
foreach ($n in 'ANTHROPIC_API_KEY','OPENROUTER_API_KEY','ZAI_API_KEY','DEEPSEEK_API_KEY',
               'CLAUDE_CODE_OAUTH_TOKEN') {
  $SECRETS[$n] = [Environment]::GetEnvironmentVariable($n)
}

# --- model tag -> tier -------------------------------------------------------------------
# The spec's `model:` column records INTENT ("this row needs judgment"). This function is the
# only place that decides a vendor, so the ladder moves in one edit.
#
# Austin 2026-08-09: three live tiers - opus, glm, deepseek. deepseek is BACK (it was collapsed
# into glm on 8/2 after the direct paid account burned 856 calls in a day) but it no longer
# touches the direct DeepSeek account at all: it goes through OpenRouter on the same key as
# glm, so there is one balance to watch and no second account that can be drained unnoticed.
function Tier($model) {
  $m = ($model | ForEach-Object { $_ }) -as [string]
  $m = $m.ToLower()
  if ($m -match 'opus|fable|sonnet|claude') { return 'opus' }
  if ($m -match 'glm|z-ai|zai')             { return 'glm' }
  return 'deepseek'   # deepseek | auto/* | free-ladder | grunt | blank - the default tier
}

# Each tier is (env block, model id, which secret must exist, how to fix it if missing).
# `resume` is the literal text of the BLOCKED notification - the exact steps, not a hint.
$TIERS = @{
  # Pay-per-token console key. oauth=$true + CLAUDE_CODE_OAUTH_TOKEN (a `claude setup-token`
  # one-year CI token) bills the Max subscription instead; flip both fields to switch back.
  # That precedence matters: ANTHROPIC_API_KEY (#3) OUTRANKS CLAUDE_CODE_OAUTH_TOKEN (#5), so
  # setting both silently bills the console key. The per-task clear below is what prevents it.
  opus = @{
    model  = 'claude-opus-5'
    secret = 'ANTHROPIC_API_KEY'
    oauth  = $false
    base   = ''                                     # native api.anthropic.com
    resume = 'ANTHROPIC_API_KEY repo secret missing. Set it (pay-per-token, dollars not subscription quota). To go back to the Max subscription instead: run `claude setup-token`, set repo secret CLAUDE_CODE_OAUTH_TOKEN, and flip secret/oauth back on this block.'
  }
  # OpenRouter publishes an Anthropic-compatible endpoint (the "Anthropic Skin") at
  # https://openrouter.ai/api - note NO /v1, Claude Code appends /v1/messages itself. The usual
  # failure is using the OpenAI base URL .../api/v1, which 404s.
  #
  # extraBody pins which UPSTREAM serves the model. Unpinned, OpenRouter's weighted routing
  # picks for you: measured 2026-08-06, glm-5.2 served by CoreWeave at $0.76/$2.42 per M vs
  # StreamLake at $0.56/$1.76 - same model, 57% cheaper. It reaches OpenRouter via
  # CLAUDE_CODE_EXTRA_BODY, a Claude Code env var whose JSON is spread into the request body;
  # the CLI has no --provider flag. Model-slug suffixes do NOT pin a provider - `:streamlake`
  # is silently ignored and `:floor`/`:nitro` are sort orders. Don't chase them.
  # order + allow_fallbacks:false = these three, cheapest first, nothing else. A bare
  # `only:["streamlake"]` would turn a StreamLake outage into a hard 404 mid-run.
  glm = @{
    model  = 'z-ai/glm-5.2'
    secret = 'OPENROUTER_API_KEY'
    base   = 'https://openrouter.ai/api'
    extraBody = '{"provider":{"order":["streamlake","baidu","novita"],"allow_fallbacks":false}}'
    resume = 'OpenRouter credit is out. Either top it up at openrouter.ai/credits, or flip the glm tier in ci/run-spec.ps1 back to base=https://api.z.ai/api/anthropic secret=ZAI_API_KEY model=glm-5.2 (that key is already set) after attaching a GLM Coding Plan at z.ai -> Billing.'
  }
  # Re-enabled 2026-08-09, through OpenRouter rather than the direct account that got burned.
  # Provider prices pulled live that day (per M tokens, in/out):
  #   StreamLake  0.068 / 0.137   <- pinned first
  #   Baidu       0.069 / 0.137
  #   DigitalOcean 0.084 / 0.168
  #   DeepSeek first-party and 12 others all sit at 0.140 / 0.280
  # i.e. the pin is worth ~2x on this model, and the whole tier is ~8x cheaper in / ~13x
  # cheaper out than glm. Same two providers as the glm pin, so one outage story, not two.
  # NOTE: there is no `-0423` snapshot on OpenRouter; the dated `-0731` build is MORE expensive
  # than the plain slug on every endpoint (cheapest 0.080/0.252). Plain slug is correct.
  deepseek = @{
    model  = 'deepseek/deepseek-v4-flash'
    secret = 'OPENROUTER_API_KEY'
    base   = 'https://openrouter.ai/api'
    extraBody = '{"provider":{"order":["streamlake","baidu","digitalocean"],"allow_fallbacks":false}}'
    resume = 'OpenRouter credit is out (deepseek tier runs on the same key as glm). Top it up at openrouter.ai/credits.'
  }
}

# --- dependency order --------------------------------------------------------------------
# parse-spec.ps1 already proved every depends-on names a real row, so this cannot loop
# forever on a dangling dep. It CAN loop on a genuine cycle, hence the explicit break.
function TopoOrder($tasks) {
  $pending = [System.Collections.ArrayList]@($tasks)
  $ordered = @()
  $emitted = @{}
  while ($pending.Count) {
    $ready = @($pending | Where-Object {
      $deps = @($_.dependsOn); ($deps.Count -eq 0) -or (($deps | Where-Object { -not $emitted[$_] }).Count -eq 0)
    })
    if (-not $ready.Count) {
      $stuck = ($pending | ForEach-Object { $_.id }) -join ', '
      throw "depends-on cycle among: $stuck"
    }
    foreach ($t in $ready) { $ordered += $t; $emitted[$t.id] = $true; $pending.Remove($t) }
  }
  return $ordered
}

# --- the check that actually decides a row ------------------------------------------------
# Runs the row's `verify:` in the TARGET repo with bash. `set -e` so a multi-line check fails
# on its first failing command instead of reporting the last one's status; -o pipefail so a
# `python x.py | tail` cannot launder a crash into exit 0.
#
# stdout and stderr are captured TOGETHER and handed to the retry as diagnostics. That is the
# whole point of running the check here: attempt 2 gets "your check failed with THIS output"
# instead of the model's own account of why it thinks it failed.
function Invoke-Verify {
  param([string]$Cmd, [string]$Dir, [int]$TimeoutMin)

  # An empty script exits 0, which would silently pass every row it touched - the exact class
  # of "check that cannot fail" this whole design exists to remove. parse-spec.ps1 refuses a
  # pending row with no verify:, so reaching here means something upstream changed; fail loud.
  if ([string]::IsNullOrWhiteSpace($Cmd)) {
    return @{ exit = 2; out = 'no verify: command on this row - refusing to pass a row that has no check' }
  }

  $sh  = Join-Path ([IO.Path]::GetTempPath()) ("verify-" + [guid]::NewGuid().ToString('N') + ".sh")
  [IO.File]::WriteAllText($sh, "set -eo pipefail`n$Cmd`n", (New-Object Text.UTF8Encoding($false)))
  $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()

  # Non-ASCII from a Python check used to crash the check itself on the runner's default
  # encoding, turning a passing row into a failed one. Set once, here, for every verify.
  $env:PYTHONIOENCODING = 'utf-8'

  $p = Start-Process -FilePath 'bash' -PassThru -NoNewWindow -ArgumentList @($sh) `
        -WorkingDirectory $Dir -RedirectStandardOutput $o -RedirectStandardError $e
  if (-not $p.WaitForExit($TimeoutMin * 60 * 1000)) {
    try { $p.Kill($true) } catch {}
    return @{ exit = 124; out = "verify command exceeded $TimeoutMin min and was killed" }
  }
  $txt = (((Get-Content $o -Raw -Encoding UTF8) ?? '') + ((Get-Content $e -Raw -Encoding UTF8) ?? '')).Trim()
  return @{ exit = $p.ExitCode; out = $txt }
}

function Trim-Tail($s, $n) {
  if (-not $s) { return '' }
  if ($s.Length -le $n) { return $s }
  return '...' + $s.Substring($s.Length - $n)
}

$ordered = TopoOrder $plan.tasks

if ($DryRun) {
  $pending = @($ordered | Where-Object { -not $_.done })
  Write-Host "$($plan.version) -> $($plan.repo)"
  foreach ($t in $ordered) {
    $tier = Tier $t.model
    $state = if ($t.done) { 'skip [x]' } else { "$tier -> $($TIERS[$tier].model)" }
    $dep = if (@($t.dependsOn).Count) { " (after $(@($t.dependsOn) -join ','))" } else { '' }
    Write-Host ("  {0,-6} {1}{2}" -f $t.id, $state, $dep)
    if (-not $t.done) { Write-Host ("         verify: {0}" -f (($t.verify -replace "`n", ' ; '))) }
  }
  Write-Host "$($pending.Count) pending, ETA under $($pending.Count * $TaskTimeoutMin) min (x$Attempts attempts worst case, capped at $BudgetMin min)"
  exit 0
}

$results = @()

# The result file is written after EVERY row, not once at the end.
#
# 2026-08-08: a null-reference on a diagnostic line threw mid-loop, $ErrorActionPreference was
# Stop, the process died before ConvertTo-Json ran, and the upload step logged "No files were
# found with the provided path: result-*.json". Two rows of finished, verified work vanished
# and the run reported nothing at all. Any crash, timeout or job-cancel past this point now
# costs at most the row in flight.
function Save-Results {
  $done  = @($results | Where-Object { $_.state -eq 'done' }).Count
  $total = @($results | Where-Object { $_.state -ne 'skipped' }).Count

  # One line per DISTINCT fix, with the rows it unblocks. Five rows waiting on one missing key
  # is one human task, not five notifications - that repetition is what made the old channel
  # unreadable and is exactly what Austin asked to kill.
  # Group-Object -Property note does NOT work here: $results holds [ordered] hashtables, and
  # Group-Object looks for a .note PROPERTY, which a Hashtable does not have - every row landed
  # in one group with an empty Name. The scriptblock reads the key instead.
  $blocked = @($results | Where-Object { $_.state -eq 'blocked' } |
               Group-Object { $_['note'] } | ForEach-Object {
                 $ids = ($_.Group | ForEach-Object { $_['id'] }) -join ', '
                 "$ids -- $($_.Name)"
               })

  # Questions/ideas/tasks stay TAGGED WITH THE ROW THAT RAISED THEM all the way to the phone.
  # Austin 2026-08-09: "so the content is not coming from one brain." Nothing merges or
  # rewrites these - the row that did the work is the only thing that speaks for it.
  # Written as explicit loops, not a pipeline: a nested ForEach-Object rebinds $_ and the
  # inner block would lose the row it belongs to.
  function Collect($field) {
    $acc = @()
    foreach ($r in $results) {
      if (-not $r[$field]) { continue }
      foreach ($x in $r[$field]) {
        if ("$x".Trim()) { $acc += [ordered]@{ id = $r['id']; text = "$x".Trim() } }
      }
    }
    return ,$acc
  }

  # `tasks` stays the spec's ROWS - the workflow, the PR gate and every past result file all
  # read that key, and renaming it to make room for human tasks would break them silently.
  # The human-task list from the models is `humanTasks`.
  $payload = [ordered]@{
    version    = $plan.version
    repo       = $plan.repo
    doc        = $plan.doc
    spec       = $plan.spec
    target     = $plan.successCriteria
    done       = $done
    total      = $total
    blocked    = $blocked
    questions  = Collect 'questions'
    ideas      = Collect 'ideas'
    humanTasks = Collect 'tasks'
    # Only a row that PASSED verify may retire a line from the project doc. A failed row's
    # opinion about what is now obsolete is worth nothing - it did not do the thing.
    retires    = ,@(Collect 'retires' | Where-Object { $id = $_.id
                                                       ($results | Where-Object { $_['id'] -eq $id -and $_['state'] -eq 'done' }).Count -gt 0 })
    tasks      = $results
  }
  [IO.File]::WriteAllText($Out, ($payload | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

foreach ($t in $ordered) {

  if ($t.done) {
    $results += [ordered]@{ id=$t.id; state='skipped'; tier=''; note='already [x] in the spec' }
    Save-Results
    continue
  }

  $elapsed = ((Get-Date) - $runStart).TotalMinutes
  if ($elapsed -ge $BudgetMin) {
    $results += [ordered]@{ id=$t.id; state='skipped'; tier=''
                            note="run budget exhausted ($([math]::Round($elapsed)) of $BudgetMin min) - re-push the spec to continue" }
    Save-Results
    continue
  }

  $tier = Tier $t.model
  $cfg  = $TIERS[$tier]
  $key  = $SECRETS[$cfg.secret]

  # A missing key is BLOCKED, never FAILED, and never silently downgraded onto a cheaper
  # model. The old rig's one unbreakable rule survives: if the named tier is unreachable,
  # the row waits. Downgrading is how a judgment row quietly becomes garbage.
  if (-not $key) {
    $results += [ordered]@{ id=$t.id; state='blocked'; tier=$tier; note=$cfg.resume }
    Save-Results
    continue
  }

  # A dependency that did not finish means this row would run on absent input - exactly the
  # 7/28 failure where rows fired with nothing and produced confident garbage.
  $failedDeps = @($t.dependsOn | Where-Object { $d = $_; ($results | Where-Object { $_.id -eq $d -and $_.state -notin @('done','skipped') }).Count })
  if ($failedDeps.Count) {
    $results += [ordered]@{ id=$t.id; state='skipped'; tier=$tier; note="upstream not done: $($failedDeps -join ', ')" }
    Save-Results
    continue
  }

  # Every row runs inside a try. One row's unhandled exception must not be able to end the run
  # and take every confirmed row's result with it - that is exactly what happened on 2026-08-08
  # when a .GetType() on a null killed the process between T3 and T6.
  try {

    # CLAUDE_CODE_OAUTH_TOKEN is cleared with the rest for the same reason they all are: a
    # leftover credential must never authenticate the next task. It also has to be cleared
    # BEFORE the gateway tiers run, because a stray subscription token on a glm row would be
    # sent to OpenRouter.
    $env:ANTHROPIC_API_KEY   = $null
    $env:ANTHROPIC_AUTH_TOKEN = $null
    $env:ANTHROPIC_BASE_URL  = $null
    $env:CLAUDE_CODE_OAUTH_TOKEN = $null
    if     ($cfg.base)  { $env:ANTHROPIC_BASE_URL = $cfg.base; $env:ANTHROPIC_AUTH_TOKEN = $key }
    elseif ($cfg.oauth) { $env:CLAUDE_CODE_OAUTH_TOKEN = $key }
    else                { $env:ANTHROPIC_API_KEY = $key }

    # Cleared for every tier, then set only where the tier defines it: api.anthropic.com has
    # no `provider` field, so leaking OpenRouter's routing block onto an opus row would send
    # a body the vendor never asked for.
    $env:CLAUDE_CODE_EXTRA_BODY = $null
    if ($cfg.extraBody) { $env:CLAUDE_CODE_EXTRA_BODY = $cfg.extraBody }

    # --model pins the MAIN turn only. Claude Code's background calls (summarisation, title,
    # subagents) send claude-* ids, and a third-party Anthropic endpoint resolves those to
    # whatever it likes - on DeepSeek that is v4-pro, i.e. the expensive model gets billed
    # while every visible flag says flash. Pinning all three leaves nothing to resolve.
    $env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $cfg.model
    $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $cfg.model
    $env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $cfg.model
    $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

    $stamp    = Get-Date
    $priorOut = $null
    $row      = $null

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {

      # The retry is fed the VERIFY COMMAND'S OWN OUTPUT, not the model's account of what went
      # wrong. Before 2026-08-09 this said "your previous attempt reported X" where X was the
      # model's self-description of a failure the runner had never actually checked - so the
      # retry banner claimed "the done-when check did not pass" when no check had been run at
      # all. Real stderr is the difference between a bug-fix pass and a re-roll.
      $fixNote = if ($priorOut) {
@"

ATTEMPT $attempt of $Attempts - BUG-FIX PASS. Your previous attempt left the verify command
FAILING. This is its real output, not a summary:

--- verify output ---
$priorOut
---------------------

Read that, find what is actually wrong, and fix it. Do not repeat the approach that just failed.

"@
      } else { '' }

      $resFile = Join-Path ([IO.Path]::GetTempPath()) "loop-$($t.id)-$attempt.json"
      Remove-Item $resFile -ErrorAction SilentlyContinue

      $prompt = @"
You are executing task $($t.id) of master spec $($plan.version), working in $WorkDir.

$($t.prompt)

DONE-WHEN: $($t.doneWhen)

THIS RUNNER DOES NOT TAKE YOUR WORD FOR IT. When you stop, it runs this exact command in
$WorkDir, and the exit code is the ONLY thing that decides whether this row counts as done:

    $($t.verify)

Run that command yourself before you finish. If it does not exit 0, you are not finished -
keep working. Saying you are done does nothing; making that command exit 0 is the whole job.
$fixNote
Do the work. Edit files directly.

Then, as your FINAL action, write this file:

  $resFile

containing one JSON object and nothing else:

{
  "resultLine": "one concrete sentence on what you actually changed - a number, a filename, a behaviour. Not 'implemented the task'.",
  "plain": "the SAME result with no jargon, for Austin on his phone: what is different now, and why that mattered. No filenames, no function names, no metric abbreviations.",
  "retires": ["exact sentences or bullets already in the project doc that your work just made FALSE or obsolete - copy them verbatim, see below"],
  "questions": ["only what Austin alone can answer: a preference, a trade-off, a credential, a decision about his own money or time"],
  "ideas": ["improvements you saw while in here but did not do"],
  "tasks": ["off-keyboard things only a human can do"]
}

The lists may be empty, and usually should be - do not pad them. Never put a question here
that you could have answered by reading the repo; go read it instead.

resultLine vs plain - write BOTH, they are not the same sentence:
  resultLine: "recall 13% -> 21%; _is_consolidation no longer returns [] on clustered levels"
  plain:      "The bot was throwing away setups when price had chopped around a level. It
               stopped doing that, and it now catches about 1 in 5 of your marked trades
               instead of 1 in 8."
The plain line is the ONLY thing that reaches his phone. If it contains a filename or an
abbreviation he did not coin, rewrite it.

"retires" is how the project doc stops accumulating stale claims. Read the doc named in the
task's `doc:` field. If a line in it says something your work just disproved, superseded or
completed, copy that line's text verbatim into "retires". A deterministic script strikes it
through with a pointer to your row - no model rewrites his notes. Leave it empty if nothing
in the doc went stale; do NOT retire something merely because you disagree with it, and never
retire a decision Austin himself made.

This file is how your row speaks for itself. Nothing downstream re-summarises your work.
"@

      Write-Host "::group::$($t.id) attempt $attempt of $Attempts [$tier -> $($cfg.model)]"

      # The prompt rides on STDIN, never argv. Passing it as an argument splits on spaces and
      # the model receives one word - a bug that silently ate three runs on 2026-07-28 and
      # looks exactly like a model refusing to use its tools.
      $inFile  = [IO.Path]::GetTempFileName()
      $outFile = [IO.Path]::GetTempFileName()
      $errFile = [IO.Path]::GetTempFileName()
      [IO.File]::WriteAllText($inFile, $prompt, (New-Object Text.UTF8Encoding($false)))

      $p = Start-Process -FilePath 'claude' -PassThru -NoNewWindow `
            -ArgumentList @('-p','--model',$cfg.model,'--permission-mode','bypassPermissions') `
            -WorkingDirectory $WorkDir `
            -RedirectStandardInput $inFile `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile

      $timedOut = -not $p.WaitForExit($TaskTimeoutMin * 60 * 1000)
      if ($timedOut) { try { $p.Kill($true) } catch {} }
      else { Write-Host ((Get-Content $outFile -Raw -Encoding UTF8) ?? '') }
      Write-Host "::endgroup::"

      # Commentary only. A missing or malformed report file is no longer able to fail a row -
      # it just means the notification loses this row's own sentence, which is a cosmetic loss.
      $raw = if (Test-Path $resFile) { (Get-Content $resFile -Raw -Encoding UTF8) } else { '' }
      $report = Read-TaskReport $raw

      # THE CHECK. Runs whether the agent timed out or not: a row killed at 25 minutes may well
      # have finished its work at minute 20, and there is no reason to throw that away unread.
      $v = Invoke-Verify -Cmd $t.verify -Dir $WorkDir -TimeoutMin $VerifyTimeoutMin
      $mins = [math]::Round(((Get-Date) - $stamp).TotalMinutes, 1)
      Write-Host "$($t.id): verify exit=$($v.exit) after attempt $attempt"
      if ($v.exit -ne 0) { Write-Host "$($t.id): verify output:`n$(Trim-Tail $v.out 2000)" }

      $note = if ($report.resultLine) { $report.resultLine }
              elseif ($timedOut)      { "agent timed out after $TaskTimeoutMin min (attempt $attempt)" }
              else                    { '(the agent wrote no resultLine)' }
      if ($v.exit -ne 0) { $note = "$note | verify failed (exit $($v.exit)): $(Trim-Tail $v.out 240)" }

      # plain falls back to note, never to empty: a row with no readable line still has to say
      # something on his phone. A FAILED row's plain line says so in words, because "T4 FAILED
      # x3 | verify failed (exit 1)" told him nothing about what to do.
      $plain = if ($report.plain)   { $report.plain }
               elseif ($v.exit -eq 0) { $note }
               elseif ($timedOut)   { "This step ran out of time after $TaskTimeoutMin minutes and did not finish. It needs to be split into smaller pieces." }
               else                 { "This step ran but its own check said the work is not actually done yet." }

      $row = [ordered]@{
        id=$t.id
        state=($(if ($v.exit -eq 0) { 'done' } else { 'failed' }))
        tier=$tier
        note=$note
        plain=$plain
        verifyExit=$v.exit
        attempts=$attempt
        minutes=$mins
        retires=$report.retires
        questions=$report.questions
        ideas=$report.ideas
        tasks=$report.tasks
      }

      if ($v.exit -eq 0) { break }
      $priorOut = Trim-Tail $v.out 2000

      # Do not start another 25-minute attempt the budget cannot pay for.
      if (((Get-Date) - $runStart).TotalMinutes -ge $BudgetMin) {
        $row.note = "$($row.note) | out of run budget, not retried"
        break
      }
    }

    $results += $row
  }
  catch {
    # Whatever went wrong here is a runner bug, not a task result. Record it as this row's
    # failure, keep every earlier row, and move on.
    $results += [ordered]@{ id=$t.id; state='failed'; tier=$tier
                            note="runner error: $($_.Exception.Message)" }
  }

  Save-Results
}

Save-Results
$done  = @($results | Where-Object { $_.state -eq 'done' }).Count
$total = @($results | Where-Object { $_.state -ne 'skipped' }).Count
$nBlocked = @($results | Where-Object { $_.state -eq 'blocked' }).Count
Write-Host "$($plan.version): $done/$total confirmed by verify, $nBlocked blocked"

# Exit 0 even on partial completion. Austin 2026-08-02: "even 90 percent completion is good."
# A red X on a run that did 9 of 10 rows teaches you to ignore red Xs.
exit 0

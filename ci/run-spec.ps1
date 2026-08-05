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
# Model routing is three env blocks over ONE binary. DeepSeek and Z.ai both publish
# Anthropic-compatible endpoints built for Claude Code, so no gateway and no translation
# layer is involved. Verified 2026-08-02: deepseek 200, anthropic 200, z.ai 401-on-bogus-key
# (alive, speaks the protocol). OmniRoute and OpenRouter are deliberately absent.

param(
  [Parameter(Mandatory=$true)][string]$Parsed,      # spec-parsed.json from parse-spec.ps1
  [Parameter(Mandatory=$true)][string]$WorkDir,     # checkout of the spec's repo: target
  [int]$TaskTimeoutMin = 25,
  [string]$Out = 'result.json',
  [switch]$DryRun          # print tier + order + ETA and spend nothing. The old -WhatIf.
)

$ErrorActionPreference = 'Stop'
$plan = Get-Content $Parsed -Raw -Encoding UTF8 | ConvertFrom-Json

# --- model tag -> tier -------------------------------------------------------------------
# The spec's `model:` column records INTENT ("this row needs judgment"). This function is the
# only place that decides a vendor, so the ladder moves in one edit. Austin 2026-08-02:
# opus while console credits last, glm-5.2 becomes top when they run out, deepseek for grunt.
# DEEPSEEK DISABLED 2026-08-02 - burned the paid DeepSeek account (856 calls on 8/1 alone).
# Every deepseek/auto/free-ladder/grunt/blank task now lands on glm (OpenRouter credit).
function Tier($model) {
  $m = ($model | ForEach-Object { $_ }) -as [string]
  $m = $m.ToLower()
  if ($m -match 'opus|fable|sonnet|claude') { return 'opus' }
  if ($m -match 'glm|z-ai|zai')             { return 'glm' }
  return 'glm'   # DEEPSEEK OFF 8/2: deepseek | auto/* | free-ladder | grunt | blank land here
}

# Each tier is (env block, model id, which secret must exist, how to fix it if missing).
# `resume` is the literal text of the BLOCKED notification - the exact steps, not a hint.
$TIERS = @{
  opus = @{
    model  = 'claude-opus-5'
    secret = 'ANTHROPIC_API_KEY'
    base   = ''                                     # native api.anthropic.com
    resume = 'Add repo secret ANTHROPIC_API_KEY (Anthropic console key), then re-run the job.'
  }
  # GLM points at OpenRouter, not Z.ai, until Austin's $30 of OpenRouter credit is spent.
  # 2026-08-02: the Z.ai key authenticates but the account returns 429 code 1113
  # "Insufficient balance or no resource package" - a valid key with nothing behind it.
  # OpenRouter publishes an Anthropic-compatible endpoint (the "Anthropic Skin") at
  # https://openrouter.ai/api - note NO /v1, Claude Code appends /v1/messages itself. The
  # usual failure is using the OpenAI base URL .../api/v1, which 404s.
  # To flip back to Z.ai once the credit is gone: swap base + secret on this one block.
  glm = @{
    model  = 'z-ai/glm-5.2'
    secret = 'OPENROUTER_API_KEY'
    base   = 'https://openrouter.ai/api'
    resume = 'OpenRouter credit is out. Either top it up, or flip the glm tier in ci/run-spec.ps1 back to base=https://api.z.ai/api/anthropic secret=ZAI_API_KEY model=glm-5.2 (that key is already set) after attaching a GLM Coding Plan at z.ai -> Billing.'
  }
  # DISABLED 2026-08-02 (Austin: burned paid DeepSeek). Tier() no longer returns 'deepseek',
  # so this block is unreachable. Kept so re-enabling is a one-line flip in Tier() + is_active
  # on the OmniRoute provider, not a rewrite.
  deepseek = @{
    model  = 'deepseek-v4-flash'
    secret = 'DEEPSEEK_API_KEY'
    base   = 'https://api.deepseek.com/anthropic'
    resume = 'Add repo secret DEEPSEEK_API_KEY (from platform.deepseek.com), then re-run the job.'
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

$ordered = TopoOrder $plan.tasks

if ($DryRun) {
  $pending = @($ordered | Where-Object { -not $_.done })
  Write-Host "$($plan.version) -> $($plan.repo)"
  foreach ($t in $ordered) {
    $tier = Tier $t.model
    $state = if ($t.done) { 'skip [x]' } else { "$tier -> $($TIERS[$tier].model)" }
    $dep = if (@($t.dependsOn).Count) { " (after $(@($t.dependsOn) -join ','))" } else { '' }
    Write-Host ("  {0,-6} {1}{2}" -f $t.id, $state, $dep)
  }
  Write-Host "$($pending.Count) pending, ETA under $($pending.Count * $TaskTimeoutMin) min"
  exit 0
}

$results = @()
$blocked = @()

foreach ($t in $ordered) {

  if ($t.done) {
    $results += [ordered]@{ id=$t.id; state='skipped'; tier=''; note='already [x] in the spec' }
    continue
  }

  $tier = Tier $t.model
  $cfg  = $TIERS[$tier]
  $key  = [Environment]::GetEnvironmentVariable($cfg.secret)

  # A missing key is BLOCKED, never FAILED, and never silently downgraded onto a cheaper
  # model. The old rig's one unbreakable rule survives: if the named tier is unreachable,
  # the row waits. Downgrading is how a judgment row quietly becomes garbage.
  if (-not $key) {
    $results += [ordered]@{ id=$t.id; state='blocked'; tier=$tier; note=$cfg.resume }
    continue
  }

  # A dependency that did not finish means this row would run on absent input - exactly the
  # 7/28 failure where rows fired with nothing and produced confident garbage.
  $failedDeps = @($t.dependsOn | Where-Object { $d = $_; ($results | Where-Object { $_.id -eq $d -and $_.state -notin @('done','skipped') }).Count })
  if ($failedDeps.Count) {
    $results += [ordered]@{ id=$t.id; state='skipped'; tier=$tier; note="upstream not done: $($failedDeps -join ', ')" }
    continue
  }

  $env:ANTHROPIC_API_KEY   = $null
  $env:ANTHROPIC_AUTH_TOKEN = $null
  $env:ANTHROPIC_BASE_URL  = $null
  if ($cfg.base) { $env:ANTHROPIC_BASE_URL = $cfg.base; $env:ANTHROPIC_AUTH_TOKEN = $key }
  else           { $env:ANTHROPIC_API_KEY = $key }

  # --model pins the MAIN turn only. Claude Code's background calls (summarisation, title,
  # subagents) send claude-* ids, and a third-party Anthropic endpoint resolves those to
  # whatever it likes - on DeepSeek that is deepseek-v4-pro, i.e. the expensive model gets
  # billed while every visible flag says flash. Pinning all three leaves nothing to resolve.
  $env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $cfg.model
  $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $cfg.model
  $env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $cfg.model
  $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

  $stamp = Get-Date
  $priorNote = $null
  $row = $null

  # One retry, framed as a bug-fix pass, before a row is finalized as failed. The retry gets
  # the first attempt's own note as context ("your last attempt said X - fix it and make
  # DONE-WHEN pass"), same tier, same worker - not a downgrade, not a different model. Two
  # tries total; a row that fails twice is a real BLOCKED/failed, not a flake.
  for ($attempt = 1; $attempt -le 2; $attempt++) {

    $fixNote = if ($priorNote) {
      "`n`nATTEMPT $attempt of 2 - this is a bug-fix pass. Your previous attempt on this exact task reported: `"$priorNote`". The done-when check did not pass. Find and fix what's actually wrong - do not repeat the same approach that just failed.`n"
    } else { '' }

    $prompt = @"
You are executing task $($t.id) of master spec $($plan.version), working in $WorkDir.

$($t.prompt)

DONE-WHEN: $($t.doneWhen)
$fixNote
Do the work. Edit files directly. Then print, as the LAST thing in your output, one line of
JSON and nothing after it:
{"done": true|false, "resultLine": "one sentence on what you actually did or why not"}
Set done=false honestly if the done-when test does not pass. A false 'done' is worse than a
failure, because it checks a row off that nobody did.
"@

    Write-Host "::group::$($t.id) attempt $attempt [$tier -> $($cfg.model)]"

    # The prompt rides on STDIN, never argv. Passing it as an argument splits on spaces and the
    # model receives one word - a bug that silently ate three runs on 2026-07-28 and looks
    # exactly like a model refusing to use its tools.
    $inFile  = [IO.Path]::GetTempFileName()
    $outFile = [IO.Path]::GetTempFileName()
    $errFile = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($inFile, $prompt, (New-Object Text.UTF8Encoding($false)))

    $p = Start-Process -FilePath 'claude' -PassThru -NoNewWindow `
          -ArgumentList @('-p','--model',$cfg.model,'--permission-mode','bypassPermissions') `
          -WorkingDirectory $WorkDir `
          -RedirectStandardInput $inFile `
          -RedirectStandardOutput $outFile -RedirectStandardError $errFile

    if (-not $p.WaitForExit($TaskTimeoutMin * 60 * 1000)) {
      try { $p.Kill($true) } catch {}
      $row = [ordered]@{ id=$t.id; state='failed'; tier=$tier; note="timed out after $TaskTimeoutMin min (attempt $attempt)"; minutes=[math]::Round(((Get-Date) - $stamp).TotalMinutes, 1) }
      Write-Host "::endgroup::"
      if ($attempt -eq 1) { $priorNote = $row.note; continue } else { break }
    }

    $stdout = (Get-Content $outFile -Raw -Encoding UTF8) ?? ''
    Write-Host $stdout
    Write-Host "::endgroup::"

    # Take the LAST JSON object carrying a "done" key. Everything else is prose around it.
    $parsed = $null
    foreach ($m in [regex]::Matches($stdout, '\{[^{}]*"done"[\s\S]*?\}')) {
      try { $o = $m.Value | ConvertFrom-Json; if ($null -ne $o.done) { $parsed = $o } } catch {}
    }

    $mins = [math]::Round(((Get-Date) - $stamp).TotalMinutes, 1)
    if ($parsed) {
      $row = [ordered]@{
        id=$t.id; state=($(if ($parsed.done) {'done'} else {'failed'})); tier=$tier
        note=$parsed.resultLine; minutes=$mins
      }
    } else {
      $tail = ($stdout.Trim() + (Get-Content $errFile -Raw -Encoding UTF8)).Trim()
      if ($tail.Length -gt 400) { $tail = $tail.Substring($tail.Length - 400) }
      $row = [ordered]@{ id=$t.id; state='failed'; tier=$tier; note="no parseable result. tail: $tail"; minutes=$mins }
    }

    if ($row.state -eq 'done' -or $attempt -eq 2) { break }
    $priorNote = $row.note
  }

  $results += $row
}

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

$payload = [ordered]@{
  version = $plan.version
  repo    = $plan.repo
  doc     = $plan.doc
  spec    = $plan.spec
  target  = $plan.successCriteria
  done    = $done
  total   = $total
  blocked = $blocked
  tasks   = $results
}
[IO.File]::WriteAllText($Out, ($payload | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))

Write-Host "$($plan.version): $done/$total done, $($blocked.Count) blocked"
# Exit 0 even on partial completion. Austin 2026-08-02: "even 90 percent completion is good."
# A red X on a run that did 9 of 10 rows teaches you to ignore red Xs.
exit 0

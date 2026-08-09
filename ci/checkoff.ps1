# checkoff.ps1 - write a finished run's state back into the spec markdown.
#
# Why this exists: nothing ever marked a row done, so a spec stayed `status: ready` with zero
# `[x]` forever. Every re-push then re-ran rows that had already landed - omen-3.4's rows ran
# three times on real opus spend, and pushing corpus-2.0 re-fired omen-3.7 minutes after
# omen-3.7's own run had finished (run 31235908719). Scoping the push to the diff hid the
# symptom; the spec having no memory was the cause.
#
# The historical objection to this - "agents edited the spec to mark rows done, and twice that
# lied" (the v2.2 Report claimed 12/15 while disk held 6/15) - does not apply now. A `[x]` here
# is written by the RUNNER, only for a row whose `verify:` command exited 0. No model can put
# one there, and no model is asked whether it deserves one.
#
# Pushed with GITHUB_TOKEN by the workflow, which by design does NOT trigger another workflow
# run - so checking off rows cannot start a second loop.

param(
  [Parameter(Mandatory=$true)][string]$Spec,
  [Parameter(Mandatory=$true)][string]$Result
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Spec))   { Write-Host "checkoff: no spec at $Spec";   exit 0 }
if (-not (Test-Path $Result)) { Write-Host "checkoff: no result at $Result"; exit 0 }

$r    = Get-Content $Result -Raw -Encoding UTF8 | ConvertFrom-Json
$done = @($r.tasks | Where-Object { $_.state -eq 'done' } | ForEach-Object { $_.id })
if (-not $done.Count) { Write-Host 'checkoff: nothing verified this run, spec untouched'; exit 0 }

$lines   = Get-Content $Spec -Encoding UTF8
# Same heading grammar as parse-spec.ps1 - hyphen, en dash or em dash.
$taskRe  = '^###\s+(?<done>\[x\]\s+)?(?<id>[A-Za-z]+\d+(?:\.\d+)*)\s*[-‒–—―−]\s*(?<title>.*)$'
$changed = @()

for ($i = 0; $i -lt $lines.Count; $i++) {
  $m = [regex]::Match($lines[$i], $taskRe)
  if (-not $m.Success) { continue }
  if ($m.Groups['done'].Success) { continue }          # already checked off
  $id = $m.Groups['id'].Value
  if ($done -notcontains $id) { continue }
  # INSERT the marker, never rebuild the line from its captured parts. `### T1 -- first row`
  # uses a double hyphen, and the heading pattern matches only the FIRST dash character, so
  # reassembling "### [x] <id> <dash> <title>" produced `### [x] T1 - - first row` - a mangled
  # heading in a file Austin reads. Caught by ci/test-pipeline.ps1 before it ever shipped.
  $lines[$i] = [regex]::Replace($lines[$i], '^(###\s+)', '${1}[x] ')
  $changed += $id
}

if (-not $changed.Count) { Write-Host 'checkoff: every verified row was already [x]'; exit 0 }

# Once every row carries [x], the spec is finished. Flipping status off `ready` is what stops
# a workflow_dispatch with a blank spec input from re-selecting a completed spec forever.
$stillOpen = @()
foreach ($l in $lines) {
  $m = [regex]::Match($l, $taskRe)
  if ($m.Success -and -not $m.Groups['done'].Success) { $stillOpen += $m.Groups['id'].Value }
}
if (-not $stillOpen.Count) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^status:\s*(ready|running)\s*$') { $lines[$i] = 'status: done'; break }
  }
  Write-Host 'checkoff: every row is [x] - spec marked status: done'
}

[IO.File]::WriteAllLines($Spec, $lines, (New-Object Text.UTF8Encoding($false)))
Write-Host "checkoff: marked [x] on $($changed -join ', ')"
if ($stillOpen.Count) { Write-Host "checkoff: still open - $($stillOpen -join ', ')" }
exit 0

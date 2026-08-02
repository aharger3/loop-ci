# parse-spec.ps1 - turn the active master spec into task JSON, deterministically.
#
# Why this exists: on 2026-07-28 the Parse AGENT read a 15-row spec and returned 8 rows.
# C2.1 C2.2 C2.3 C3.2 C4.2 C4.3 C5.2 were never seen by the run at all, and because
# run-spec.js treated a dependency missing from the plan as "external, therefore satisfied",
# the two judgment rows fired with no input and died. The whole night produced 4 rows.
#
# The spec format is ours and it is regular, so an LLM in the parse path is pure downside:
# it is the single highest-cost dependency in a run (a wrong parse silently voids the night)
# and it buys nothing a regex cannot do. This runs before a single token is spent, and it
# CANNOT drop a row - if any "###" heading fails to parse, it exits non-zero and pages.
#
# ponytail: kept in PowerShell on purpose. The reason it was PS (no file I/O in a Workflow
# body) is gone in CI, but this parser is the one battle-tested piece of the old loop and a
# rewrite buys nothing. `pwsh` ships on ubuntu-latest. Only three things changed for CI:
# FOCUS.md indirection is gone (the spec file is self-describing), Fail no longer curls ntfy
# (the workflow owns all four notifications), and `repo:` replaced the Windows `path:`.

param(
  [Parameter(Mandatory=$true)][string]$Spec,
  [string]$Out = 'spec-parsed.json'
)

$ErrorActionPreference = 'Stop'

# Fail loudly to stderr and exit 3. The workflow turns exit 3 into the single BLOCKED ntfy,
# so this script must never notify on its own - that is how the old rig got spammy.
function Fail($msg) {
  [Console]::Error.WriteLine("PARSE FAIL: $msg")
  exit 3
}

if (-not (Test-Path $Spec)) { Fail "spec not found at $Spec" }
$specTxt = Get-Content $Spec -Raw -Encoding UTF8

function SpecField($name) {
  $m = [regex]::Match($specTxt, "(?m)^${name}:\s*(.+?)\s*$")
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  return ''
}

$repo    = SpecField 'repo'
$doc     = SpecField 'doc'      # optional: vault path, e.g. Projects/TradingBot.md
$version = SpecField 'version'
if (-not $version) { $version = [IO.Path]::GetFileNameWithoutExtension($Spec) }
$status  = SpecField 'status'

# A spec with no repo: has nowhere to put its work. Catching it here costs nothing;
# catching it after the tokens are spent costs a night.
if (-not $repo) { Fail "spec has no 'repo:' line (expected owner/name, e.g. aharger3/tradingbot)" }
if ($status -and $status -notin @('ready','running')) { Fail "spec status is '$status', expected 'ready'" }

# -Encoding UTF8 is not optional: without it PowerShell 5.1 reads the file as
# cp1252 and every em dash in a heading becomes mojibake, so no task matches.
$lines = Get-Content $Spec -Encoding UTF8

# A task heading: "### C2.2 - title", "### [x] C1.3 — title". Hyphen, en dash or em dash.
# "## C1 — ..." is a SECTION header (two hashes) and is deliberately not matched.
$taskRe = '^###\s+(?<done>\[x\]\s+)?(?<id>[A-Za-z]+\d+(?:\.\d+)*)\s*[-\u2012\u2013\u2014\u2015\u2212]\s*(?<title>.*)$'

# Every "###" heading in the file, so we can prove none was skipped.
$allHeadings = @()
$taskStarts  = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^###\s') {
    $allHeadings += [pscustomobject]@{ Index = $i; Text = $lines[$i] }
    if ($lines[$i] -match $taskRe) { $taskStarts += $i }
  }
}

if ($allHeadings.Count -eq 0) { Fail "no '###' task headings found in $Spec" }

$unmatched = $allHeadings | Where-Object { $_.Text -notmatch $taskRe }
if ($unmatched) {
  $names = ($unmatched | ForEach-Object { $_.Text.Trim() }) -join ' | '
  Fail ("$($unmatched.Count) '###' heading(s) did not parse as tasks, so a row would have " +
        "been silently dropped: $names")
}

# Matches "name:", "- name:", "**name:**" and "- **name:** " in one pattern.
function FieldPat($name) { "(?im)(?:^|\|)\s*(?:[-*]\s+)?\*{0,2}$name\*{0,2}\s*:\s*\*{0,2}\s*([^|\r\n]+)" }
# Values arrive as `z-ai/glm-5.2` or **bold** - the markup is not part of the value.
function Clean($v) { ($v -replace '[`*]', '').Trim() }

$tasks = @()
for ($t = 0; $t -lt $taskStarts.Count; $t++) {
  $start = $taskStarts[$t]
  $end   = if ($t + 1 -lt $taskStarts.Count) { $taskStarts[$t + 1] - 1 } else { $lines.Count - 1 }

  $m  = [regex]::Match($lines[$start], $taskRe)
  $id = $m.Groups['id'].Value
  $isDone = $m.Groups['done'].Success

  # Body = everything until the next task heading, minus any later "## " section header
  # that belongs to the NEXT claim block rather than this task.
  $bodyLines = @()
  for ($j = $start + 1; $j -le $end; $j++) {
    if ($lines[$j] -match '^##\s') { break }
    $bodyLines += $lines[$j]
  }
  $body = ($bodyLines -join "`n")

  function Field($pattern) {
    $mm = [regex]::Match($body, $pattern)
    if ($mm.Success) { return $mm.Groups[1].Value.Trim() }
    return ''
  }

  # Field lines come in two dialects, both live in real specs:
  #   "model: glm | depends-on: C2.1 | files: research\x.md"   pipe-separated, bare
  #   "- model: `z-ai/glm-5.2`" / "- **done-when:** ..."       markdown bullet, bold label,
  #                                                            value in backticks
  # v2.5-ledger is written entirely in the bullet dialect. The bare-only patterns matched
  # nothing in it: every row came out with an empty model and no done-when, so the parser
  # bailed on row one and the night would have run zero tasks.
  # A model line often trails prose: "claude-fable-5 (direct route)", "z-ai/glm-5.2
  # orchestrating local moondream". The model is the first token; the rest is commentary,
  # and passing it through produces a model id the gateway cannot resolve.
  $model   = Clean (Field (FieldPat 'model'))
  if ($model) { $model = ($model -split '\s+')[0].TrimEnd(',', ';') }
  $effort  = Clean (Field (FieldPat 'effort'))
  $files   = Clean (Field (FieldPat 'files'))
  $depsRaw = Clean (Field (FieldPat 'depends-on'))

  # done-when wraps across lines; continuation lines are INDENTED, so it runs until a blank
  # line, a bullet at column 0 (the next field), a KILL:, or the end of the body.
  $dwPat = '(?ims)^\s*(?:[-*]\s+)?\*{0,2}done-when\*{0,2}\s*:\s*\*{0,2}\s*(.+?)(?=\r?\n\s*\r?\n|\r?\n[-*]\s|\r?\nKILL:|\z)'
  $dwm = [regex]::Match($body, $dwPat)
  $doneWhen = if ($dwm.Success) { ((Clean $dwm.Groups[1].Value) -replace '\s+', ' ').Trim() } else { '' }

  $deps = @()
  if ($depsRaw) {
    # "L0.5 (tunnel), L0.6 (ntfy)" -> drop the parentheticals before splitting.
    $d = ($depsRaw -replace '\([^)]*\)', ' ')
    if ($d -match '(?i)\b(everything|all)\b') {
      # L6.1 says "depends-on: everything" - i.e. run last. Expanded to real ids below so
      # the dangling-dependency check still sees only ids that exist.
      $deps = @('*ALL*')
    } else {
      $deps = @($d -split '[,\s]+' | Where-Object { $_ -and $_ -ne 'and' })
    }
  }

  # Prompt = the whole body (KILL lines included - they are instructions), minus the
  # metadata line, so the agent still sees the prose that describes the work.
  $prompt = ($body -replace '(?im)^\s*(?:[-*]\s+)?\*{0,2}(model|effort|files|depends-on)\*{0,2}\s*:[^\r\n]*\r?\n', '').Trim()
  if (-not $prompt) { $prompt = $m.Groups['title'].Value.Trim() }

  if (-not $doneWhen) { Fail "task $id has no 'done-when:' line - refusing to run a row with no success test" }

  $tasks += [ordered]@{
    id        = $id
    model     = $model
    effort    = $effort
    files     = $files
    prompt    = ($m.Groups['title'].Value.Trim() + "`n" + $prompt)
    doneWhen  = $doneWhen
    dependsOn = $deps
    done      = [bool]$isDone
  }
}

if ($tasks.Count -ne $allHeadings.Count) {
  Fail "parsed $($tasks.Count) tasks but the spec has $($allHeadings.Count) '###' headings"
}

# "depends-on: everything" means "runs last" - expand to every other row before the check.
foreach ($t in $tasks) {
  if ($t.dependsOn -contains '*ALL*') {
    $t.dependsOn = @($tasks | Where-Object { $_.id -ne $t.id } | ForEach-Object { $_.id })
  }
}

# Every depends-on must name a task that exists in this spec. A dep that does not resolve is
# exactly what let C5.3/C6.1 run empty on 7/28 - run-spec.js read a missing dep as "external".
$ids = @{}
foreach ($t in $tasks) { $ids[$t.id] = $true }
$dangling = @()
foreach ($t in $tasks) {
  foreach ($d in $t.dependsOn) { if (-not $ids.ContainsKey($d)) { $dangling += "$($t.id) -> $d" } }
}
if ($dangling) { Fail ("depends-on names a task not in the spec: " + ($dangling -join ', ')) }

$payload = [ordered]@{
  repo            = $repo
  doc             = $doc
  version         = $version
  spec            = $Spec
  successCriteria = (SpecField 'target')
  parsedAt        = (Get-Date).ToString('o')
  tasks           = $tasks
}

# Split-Path returns '' for a bare filename, and New-Item -Path '' throws. The old default
# was always an absolute tmp\ path so this never came up; in CI the output is repo-relative.
$outDir = Split-Path $Out
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
# Set-Content -Encoding UTF8 emits a BOM on PS 5.1, which makes strict JSON parsers
# choke on char 0. WriteAllText with a no-BOM encoder avoids it.
$json = $payload | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($Out, $json, (New-Object System.Text.UTF8Encoding($false)))

$pending = @($tasks | Where-Object { -not $_.done }).Count
Write-Host ("parsed {0} tasks ({1} pending, {2} already [x]) from {3}" -f `
            $tasks.Count, $pending, ($tasks.Count - $pending), (Split-Path $Spec -Leaf))
Write-Host "wrote $Out"
exit 0

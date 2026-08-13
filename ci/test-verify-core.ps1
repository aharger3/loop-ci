# test-verify-core.ps1 - self-check for TopoOrder and Invoke-Verify. Run: pwsh ci/test-verify-core.ps1
#
# These two decide a row's fate and had no test of any kind: TopoOrder picks what runs and in
# what order, Invoke-Verify decides pass or fail. The cycle branch in TopoOrder and the
# empty-command guard in Invoke-Verify had never been executed by anything.
#
# Spends nothing: TopoOrder is pure, and the verify cases are `true`/`false`/`sleep` in a temp dir.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'verify-core.ps1')

$fails = 0
function Expect($name, $cond, $detail) {
  if ($cond) { Write-Host "ok   $name" } else { Write-Host "FAIL $name : $detail"; $script:fails++ }
}
function Task($id, $deps) { [pscustomobject]@{ id = $id; dependsOn = @($deps) } }
function Order($tasks) { (TopoOrder $tasks | ForEach-Object { $_.id }) -join ',' }

# --------------------------------------------------------------------------- TopoOrder ------
Expect 'no deps keeps spec order' ((Order @((Task 'T1' @()), (Task 'T2' @()))) -eq 'T1,T2') 'reordered independent rows'
Expect 'a dependency is honoured' ((Order @((Task 'T2' @('T1')), (Task 'T1' @()))) -eq 'T1,T2') 'ran a row before its dep'
Expect 'a chain is honoured'      ((Order @((Task 'T3' @('T2')), (Task 'T2' @('T1')), (Task 'T1' @()))) -eq 'T1,T2,T3') 'chain out of order'
# `depends-on: everything` is the common shape for a final report row, and it must land LAST.
Expect 'the everything row is last' ((Order @((Task 'T5' @('T1','T2')), (Task 'T1' @()), (Task 'T2' @()))) -match ',T5$') 'report row did not run last'
# Two rows ready at once must both come out, and exactly once each - an earlier ArrayList.Remove
# inside a foreach over the same collection is exactly how a row goes missing.
$multi = Order @((Task 'T1' @()), (Task 'T2' @()), (Task 'T3' @()), (Task 'T4' @('T1','T2','T3')))
Expect 'every row is emitted once' (($multi -split ',').Count -eq 4 -and ($multi -split ',' | Sort-Object -Unique).Count -eq 4) "got [$multi]"

# The explicit break. Without it this loops forever and the row job burns its 330 minutes.
$cycled = $false
try { TopoOrder @((Task 'T1' @('T2')), (Task 'T2' @('T1'))) | Out-Null }
catch { $cycled = "$_" -match 'cycle' }
Expect 'a cycle throws, it does not hang' $cycled 'no cycle error raised'

# ------------------------------------------------------------------------ Invoke-Verify -----
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("vtest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
'hello' | Set-Content (Join-Path $tmp 'present.txt')
function V($cmd, $min = 1) { Invoke-Verify -Cmd $cmd -Dir $tmp -TimeoutMin $min }

Expect 'a passing check exits 0'  ((V 'true').exit -eq 0)                    'true did not pass'
Expect 'a failing check exits 1'  ((V 'false').exit -ne 0)                   'false did not fail'
Expect 'the check runs in the target dir' ((V 'test -f present.txt').exit -eq 0) 'wrong working directory'

# THE guard. An empty command is an empty bash script, which exits 0 - so before this existed,
# a row with no check passed unconditionally. parse-spec.ps1 now refuses such a row, so this is
# the second line of defence, and it must never be allowed to rot back to 0.
foreach ($empty in @('', '   ', "`n")) {
  Expect "an empty check NEVER passes [$($empty -replace '\s','.')]" ((V $empty).exit -eq 2) 'an empty check returned a passing exit'
}

# set -e: a multi-line check reports its FIRST failure, not the last command's status.
Expect 'set -e stops at first failure' ((V "false`ntrue").exit -ne 0) 'a later true laundered an earlier failure'
Expect 'a multi-line check can pass'   ((V "true`ntest -f present.txt").exit -eq 0) 'a good multi-line check failed'
# pipefail: `something-that-crashes | tail` must not launder the crash into exit 0.
Expect 'pipefail catches a crash mid-pipe' ((V 'false | tail -1').exit -ne 0) 'a pipe laundered a crash into a pass'

# Diagnostics. This is the whole reason verify runs here and not inside the model's turn:
# attempt 2 is handed the command's REAL output, not the model's account of it.
$o = V 'echo out-marker; echo err-marker >&2; false'
Expect 'stdout is captured' ($o.out -match 'out-marker') "lost stdout: [$($o.out)]"
Expect 'stderr is captured' ($o.out -match 'err-marker') "lost stderr: [$($o.out)]"

# Timeout is 124, the same code timeout(1) uses, and it must not be confused with a plain fail.
$t = Invoke-Verify -Cmd 'sleep 20' -Dir $tmp -TimeoutMin ([double]0.05)
Expect 'a hung check is killed as 124' ($t.exit -eq 124) "got exit $($t.exit)"

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($fails) { Write-Host "`n$fails FAILED"; exit 1 }
Write-Host "`nall verify-core checks pass"

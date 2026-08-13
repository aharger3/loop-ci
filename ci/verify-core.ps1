# verify-core.ps1 - the two functions that decide a row's fate, split out of run-spec.ps1 so
# ci/test-verify-core.ps1 can run them without executing a spec.
#
# Dot-sourced by run-spec.ps1; same arrangement as ci/result-parse.ps1 and for the same reason.
# Nothing here is new - it was moved verbatim on 2026-08-13 because it had no test at all, and
# these are precisely the two places where a bug passes a row that should have failed.

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
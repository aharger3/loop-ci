# result-parse.ps1 - the one rule for "did this task report done?"
#
# Dot-sourced by run-spec.ps1. It lives in its own file so ci/test-result-parse.ps1 can run it
# without executing a whole spec.
#
# 2026-08-06..08: the sentinel-file handshake returned done=true exactly ZERO times across
# omen-3.6, omen-corpus-1.0 and omen-3.7 - 16 attempts, glm and opus tiers, every row recorded
# failed and every downstream row skipped as "upstream not done". The work itself was fine and
# sitting in the PR each time. The old guard was `if ($null -ne $o.done)`: a 'done' that is an
# empty string, an empty array, or anything else non-boolean is NOT $null, so the runner
# announced "result via file", then read that value as false. The log printed `done=` with
# nothing after it and never printed the file's bytes, so three runs burned without a diagnosis.
#
# Two rules follow from that:
#   1. Only a real boolean counts. Anything else returns $null, which lets the stdout fallback
#      still have its shot and forces the caller to log the raw bytes.
#   2. A "true"/"false" STRING is normalised to a boolean before it is returned. PowerShell
#      treats the string "false" as truthy, so passing one through unconverted would check off
#      a row that the model explicitly said it had not finished - the exact failure the
#      sentinel exists to prevent.
function Read-TaskResult {
  param([string]$Json)

  if ([string]::IsNullOrWhiteSpace($Json)) { return $null }
  try { $o = $Json | ConvertFrom-Json } catch { return $null }
  if ($null -eq $o) { return $null }

  $d = $o.done
  if ($d -is [bool]) { return $o }
  if ("$d" -in @('true', 'false')) { $o.done = [bool]::Parse("$d"); return $o }
  return $null
}

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

  # A lone JSON array value (`[{"done": true}]` instead of `{"done": true}`) parses fine but
  # `.done` on the array itself is silently $null, not an error - collapse to the last element
  # so that shape gets read instead of rejected as done=$null.
  if ($o -is [array]) { $o = $o[-1] }
  if ($null -eq $o) { return $null }

  $d = $o.done
  if ($d -is [bool]) { return $o }
  if ("$d" -in @('true', 'false')) { $o.done = [bool]::Parse("$d"); return $o }
  return $null
}

# Read-TaskReport - what a row says about ITSELF, now that it no longer decides its own state.
#
# 2026-08-09: `verify:` exits decide done/failed, so a missing or malformed 'done' field can no
# longer fail a row. That flips the parsing rule on its head. Read-TaskResult above is STRICT on
# purpose (a non-boolean must be rejected so it can never check off a row); this one is LENIENT
# on purpose, because everything it reads is commentary - a resultLine, and the questions/ideas/
# tasks the row wants Austin to see. Losing those to a strict parse costs the notification its
# entire content and costs nothing else. So: take what parses, ignore what does not.
#
# Austin 2026-08-09: "so the content is not coming from one brain." Each row writes its own
# summary and its own questions. Nothing downstream re-summarises them - the notification is a
# concatenation of N agents' own words, not one agent's retelling of work it did not do.
function Read-TaskReport {
  param([string]$Json)

  $empty = [ordered]@{ resultLine = ''; questions = @(); ideas = @(); tasks = @() }
  if ([string]::IsNullOrWhiteSpace($Json)) { return $empty }
  try { $o = $Json | ConvertFrom-Json } catch { return $empty }
  if ($null -eq $o) { return $empty }
  if ($o -is [array]) { $o = $o[-1] }
  if ($null -eq $o) { return $empty }

  # A model that writes "questions": "just one" instead of a list is being helpful, not wrong.
  # Coerce rather than drop - a dropped question is a question Austin never gets asked.
  function AsList($v) {
    if ($null -eq $v) { return @() }
    if ($v -is [string]) { return @($v.Trim() | Where-Object { $_ }) }
    return @($v | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
  }

  # resultLine is the one field with a fallback chain: some models reach for 'summary' or
  # 'note' out of habit, and the line is what Austin actually reads in the notification.
  $line = @($o.resultLine, $o.summary, $o.note | Where-Object { $_ -is [string] -and $_.Trim() } |
            Select-Object -First 1)
  [ordered]@{
    resultLine = if ($line.Count) { "$($line[0])".Trim() } else { '' }
    questions  = AsList $o.questions
    ideas      = AsList $o.ideas
    tasks      = AsList $o.tasks
  }
}

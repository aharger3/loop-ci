# vault-sync.ps1 - put the run's summary into the Obsidian vault, deterministically.
#
# What this REPLACED and why: until 2026-08-09 the report job cloned the vault, installed
# Claude Code, and had ONE glm agent rewrite the entire project doc from the run results. Three
# things were wrong with that. It is one brain re-narrating six rows' work, which is exactly
# what Austin rejected ("so the content is not coming from one brain"). It ran a full Claude
# turn inside a job that also owns the notifications, so when it overran, the JOB timed out and
# a clean 16-row run paged "Loop never started" (run 31122686346). And it could rewrite - i.e.
# delete - text no run had anything to do with.
#
# This does none of that. No model, no network beyond git, no judgement: it splices the rows'
# OWN sentences into the note. Austin 2026-08-09: "all mds go in my obsidian, but i want the
# summary as a link because it would be too much to read in a notification." This file is that
# link's destination.
#
# Writes: one "Last loop run" block per spec version (replaced in place on a re-run, so it
# never grows), plus append-only bullets under the note's Agent Questions / Agent Ideas /
# Human Tasks headings, deduped on exact text so a re-run cannot double them.

param(
  [Parameter(Mandatory=$true)][string]$Results,    # dir of result-*.json
  [Parameter(Mandatory=$true)][string]$VaultDir,   # checkout of the vault repo
  [string]$DocOut = 'vault-doc.txt'                # where to write the primary doc's rel path
)

$ErrorActionPreference = 'Stop'

$files = @(Get-ChildItem $Results -Filter *.json -Recurse -ErrorAction SilentlyContinue)
if (-not $files.Count) { Write-Host 'vault-sync: no result files'; exit 0 }

$primary = $null

foreach ($f in $files) {
  $r = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  if (-not $r.doc) { Write-Host "vault-sync: $($r.version) has no doc: field, skipping"; continue }

  $path = Join-Path $VaultDir $r.doc
  if (-not (Test-Path $path)) {
    # Never invent a note. A doc: pointing at nothing is a spec bug worth seeing in the log,
    # not a new file appearing in the vault where nobody expects one.
    Write-Host "::warning::vault-sync: $($r.doc) does not exist in the vault - skipping $($r.version)"
    continue
  }

  $text  = Get-Content $path -Raw -Encoding UTF8
  $lines = [System.Collections.ArrayList]@($text -split "\r?\n")

  # ---- 1. the run block ------------------------------------------------------------------
  $marker = "## Last loop run - $($r.version)"
  $block  = [System.Collections.ArrayList]@()
  [void]$block.Add($marker)
  [void]$block.Add('')
  [void]$block.Add("$($r.done)/$($r.total) rows confirmed by their own verify command. Target repo ``$($r.repo)``.")
  [void]$block.Add('')

  # Plain-language first, table second. Austin 2026-08-09: the report was "very code talk - hard
  # to understand what was productive." So the note leads with each row's OWN jargon-free
  # sentence and keeps the engineer line in the table below it, where it is still greppable.
  [void]$block.Add('**What changed**')
  [void]$block.Add('')
  foreach ($t in $r.tasks) {
    $say = if ("$($t.plain)".Trim()) { "$($t.plain)" } else { "$($t.note)" }
    $say = ($say -replace '\r?\n', ' ').Trim()
    $lead = if ($t.state -eq 'done') { '✅' } else { '❌ still stuck —' }
    [void]$block.Add("- $lead $say")
  }
  [void]$block.Add('')
  [void]$block.Add('<details><summary>Technical detail per row</summary>')
  [void]$block.Add('')
  [void]$block.Add('| row | state | model | min | verify | what it did |')
  [void]$block.Add('|---|---|---|---|---|---|')
  foreach ($t in $r.tasks) {
    $note = ("$($t.note)" -replace '\|', '\|' -replace '\r?\n', ' ')
    [void]$block.Add("| $($t.id) | $($t.state) | $($t.tier) | $($t.minutes) | exit $($t.verifyExit) | $note |")
  }
  [void]$block.Add('')
  [void]$block.Add('</details>')
  [void]$block.Add('')

  # Replace the previous block for THIS version if one is there, so a re-pushed spec updates
  # its section instead of stacking a second copy under the same heading.
  $startIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].TrimEnd() -eq $marker) { $startIdx = $i; break } }
  if ($startIdx -ge 0) {
    $endIdx = $lines.Count
    for ($i = $startIdx + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##\s') { $endIdx = $i; break } }
    $lines.RemoveRange($startIdx, $endIdx - $startIdx)
    $lines.InsertRange($startIdx, $block)
  } else {
    # New block goes in front of the first standing section (Research / Agent Questions), so
    # current state reads before backlog. No such heading -> append at the end.
    $at = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^##\s+.*(Research|Agent Questions|Agent Ideas|Human Tasks|Next build step)') { $at = $i; break }
    }
    if ($at -ge 0) { $lines.InsertRange($at, $block) }
    else { [void]$block.Insert(0, ''); $lines.AddRange($block) }
  }

  # ---- 2. questions / ideas / human tasks, in the rows' own words -------------------------
  # Appended under whichever heading already owns them. Each bullet is tagged with the row that
  # raised it, so a question is traceable back to the agent that hit the wall.
  $sections = @(
    @{ match = 'Agent Questions'; items = $r.questions;   fallback = '## 🤖 Agent Questions' },
    @{ match = 'Agent Ideas';     items = $r.ideas;       fallback = '## 💡 Agent Ideas' },
    @{ match = 'Human Tasks';     items = $r.humanTasks;  fallback = '## 🧍 Human Tasks' }
  )

  foreach ($s in $sections) {
    $items = @($s.items | Where-Object { $_ -and $_.text })
    if (-not $items.Count) { continue }

    $hIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^#{2,3}\s+.*$($s.match)") { $hIdx = $i; break } }
    if ($hIdx -lt 0) {
      # No such heading in this note - create it at the end rather than dropping the content.
      [void]$lines.Add('')
      [void]$lines.Add($s.fallback)
      $hIdx = $lines.Count - 1
    }

    # End of the section = the next heading of the same or higher level.
    $insertAt = $lines.Count
    for ($i = $hIdx + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^#{1,3}\s') { $insertAt = $i; break } }
    while ($insertAt -gt $hIdx + 1 -and -not $lines[$insertAt - 1].Trim()) { $insertAt-- }

    $add = @()
    foreach ($it in $items) {
      $t = "$($it.text)".Trim()
      if (-not $t) { continue }
      # Dedup on the text itself, anywhere in the note. A re-pushed spec re-asks the same
      # question every run otherwise, and a note that repeats itself stops being read.
      if (($lines -join "`n").Contains($t)) { continue }
      $add += "- [ ] $t — $($r.version) $($it.id)"
    }
    if ($add.Count) { $lines.InsertRange($insertAt, [string[]]$add) }
  }

  # ---- 3. SUBTRACT: strike the lines this run made false ---------------------------------
  # Austin's vault rule is "always adding and subtracting" - a note that only ever grows stops
  # being true. Until now this script could only add, so every superseded claim sat there
  # looking current (omen-3.8's own note still asserted things omen-3.7 had already fixed).
  #
  # This is a STRIKETHROUGH, never a delete, and only a row that PASSED verify may ask for one
  # (run-spec.ps1 filters the list). No model rewrites the note - a row nominates exact text it
  # just disproved, and the match is literal. Guards, because the failure mode is losing his
  # writing: nothing under 25 chars (too generic), never a heading, never something already
  # struck, and never inside a `## Last loop run` block this script owns.
  $retired = 0
  foreach ($it in @($r.retires | Where-Object { $_ -and $_.text })) {
    $needle = "$($it.text)".Trim().TrimStart('-', '*', ' ').Trim()
    if ($needle.Length -lt 25) { continue }

    $inOwn = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^##\s+Last loop run') { $inOwn = $true; continue }
      elseif ($lines[$i] -match '^##\s')           { $inOwn = $false }
      if ($inOwn) { continue }
      if ($lines[$i] -match '^#{1,6}\s')  { continue }
      if ($lines[$i] -like '*~~*')        { continue }
      if (-not $lines[$i].Contains($needle)) { continue }

      $lines[$i] = "~~$($lines[$i].Trim())~~ <!-- retired by $($r.version) $($it.id) -->"
      $retired++
      break   # one line per nomination; a repeated sentence is a doc problem, not ours
    }
  }
  if ($retired) { Write-Host "vault-sync: struck $retired stale line(s) in $($r.doc)" }

  [IO.File]::WriteAllText($path, (($lines -join "`n").TrimEnd() + "`n"), (New-Object Text.UTF8Encoding($false)))
  Write-Host "vault-sync: updated $($r.doc) for $($r.version) ($($r.done)/$($r.total), $(@($r.questions).Count) q, $(@($r.ideas).Count) ideas, $(@($r.humanTasks).Count) tasks)"
  if (-not $primary) { $primary = $r.doc }
}

# The workflow turns this into the "Results" button on the notification. One doc, because the
# notification gets one extra button - if a push ran three specs, the first one with a doc wins
# and the run page still has all three.
if ($primary) { [IO.File]::WriteAllText($DocOut, $primary, (New-Object Text.UTF8Encoding($false))) }
exit 0

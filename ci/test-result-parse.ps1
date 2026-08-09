# Self-check for ci/result-parse.ps1. Run: pwsh ci/test-result-parse.ps1
# Every case below is a shape the loop has actually seen or was one model away from seeing.
. (Join-Path $PSScriptRoot 'result-parse.ps1')

$fails = 0
function Check($name, $json, $expectDone) {
  $r = Read-TaskResult $json
  $got = if ($null -eq $r) { '<rejected>' } else { $r.done }
  if ("$got" -ne "$expectDone") {
    Write-Host "FAIL $name : expected [$expectDone] got [$got]"
    $script:fails++
  } else {
    Write-Host "ok   $name -> $got"
  }
}

Check 'plain true'        '{"done": true, "resultLine": "x"}'   $true
Check 'plain false'       '{"done": false, "resultLine": "x"}'  $false
Check 'string true'       '{"done": "true"}'                    $true
# The one that matters: "false" is a truthy STRING in PowerShell. Unnormalised it would check
# off a row the model said it did not finish.
Check 'string false'      '{"done": "false"}'                   $false

# Everything below must be REJECTED, not read as false, so the stdout fallback still runs and
# the caller dumps the bytes. The empty-string case is the 2026-08-06..08 silent killer.
Check 'empty string done' '{"done": "", "resultLine": ""}'      '<rejected>'
Check 'empty array done'  '{"done": [], "resultLine": []}'      '<rejected>'
Check 'no done key'       '{"resultLine": "x"}'                 '<rejected>'
Check 'null done'         '{"done": null}'                      '<rejected>'
Check 'nested done'       '{"done": {"value": true}}'           '<rejected>'
Check 'not json'          'Task complete!'                      '<rejected>'
Check 'empty file'        ''                                    '<rejected>'
Check 'whitespace only'   "  `n "                               '<rejected>'

# A top-level JSON array parses fine, but `.done` on the array itself is $null with no error -
# must resolve to the last element, not read as a rejected/false 'done'.
Check 'json array wrapper' '[{"done": true, "resultLine": "final"}]' $true

if ($fails) { Write-Host "$fails FAILED"; exit 1 }
Write-Host 'all result-parse checks pass'

# --- Read-TaskReport ------------------------------------------------------------------------
# Deliberately the MIRROR IMAGE of the checks above. Read-TaskResult must reject anything it is
# not certain about, because it used to decide a row's fate. Read-TaskReport must salvage
# anything it can, because since 2026-08-09 it only carries commentary - and a dropped question
# is a question Austin never gets asked.
Write-Host ''
function CheckReport($name, $json, $line, $nQ) {
  $r = Read-TaskReport $json
  $gotQ = @($r.questions).Count
  if ("$($r.resultLine)" -ne "$line" -or $gotQ -ne $nQ) {
    Write-Host "FAIL $name : expected line [$line] q=$nQ, got [$($r.resultLine)] q=$gotQ"
    $script:fails++
  } else { Write-Host "ok   $name -> '$($r.resultLine)' q=$gotQ" }
}

CheckReport 'normal'        '{"resultLine":"did x","questions":["a","b"],"ideas":[],"tasks":[]}' 'did x' 2
CheckReport 'no lists'      '{"resultLine":"did x"}'                                             'did x' 0
CheckReport 'string q'      '{"resultLine":"x","questions":"just one"}'                          'x'     1
CheckReport 'summary alias' '{"summary":"used the wrong key"}'                                   'used the wrong key' 0
CheckReport 'array wrapper' '[{"resultLine":"last one","questions":["q"]}]'                      'last one' 1
# The shapes that used to FAIL A ROW now cost nothing but a blank line in the notification.
CheckReport 'legacy done'   '{"done":true,"resultLine":"still readable"}'                        'still readable' 0
CheckReport 'not json'      'Task complete!'                                                     ''      0
CheckReport 'empty'         ''                                                                   ''      0
CheckReport 'blank q drop'  '{"resultLine":"x","questions":["","  ","real"]}'                    'x'     1

# ---- plain + retires (2026-08-09) -----------------------------------------------------------
# `plain` is the phone line, `resultLine` is the table line. Both are the ROW'S own words - the
# distinction is register, not authorship. Empty plain is fine; run-spec.ps1 owns the fallback,
# because only it knows whether the row passed, timed out or failed its check.
function CheckPlain($name, $json, $plain, $nRet) {
  $r = Read-TaskReport $json
  $gotR = @($r.retires).Count
  if ("$($r.plain)" -ne "$plain" -or $gotR -ne $nRet) {
    Write-Host "FAIL $name : expected plain [$plain] ret=$nRet, got [$($r.plain)] ret=$gotR"
    $script:fails++
  } else { Write-Host "ok   $name -> plain '$($r.plain)' ret=$gotR" }
}

CheckPlain 'plain read'     '{"resultLine":"recall 13%->21%","plain":"It catches more of your trades now."}' 'It catches more of your trades now.' 0
CheckPlain 'plain absent'   '{"resultLine":"recall 13%->21%"}'                                   ''      0
CheckPlain 'plain alias'    '{"plainLine":"aliased through"}'                                    'aliased through' 0
CheckPlain 'retires list'   '{"plain":"p","retires":["one stale claim","another"]}'              'p'     2
CheckPlain 'retires string' '{"plain":"p","retires":"just the one"}'                             'p'     1
CheckPlain 'retires absent' '{"plain":"p"}'                                                      'p'     0
# resultLine must NOT leak into plain - a jargon line on his phone is the bug being fixed.
CheckPlain 'no leak'        '{"resultLine":"_is_consolidation returns [] at signal_runner.py:457"}' ''    0

if ($fails) { Write-Host "$fails FAILED"; exit 1 }
Write-Host 'all result-parse + result-report checks pass'

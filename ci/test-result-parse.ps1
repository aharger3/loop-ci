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

if ($fails) { Write-Host "$fails FAILED"; exit 1 }
Write-Host 'all result-parse checks pass'

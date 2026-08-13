# test-parse.ps1 - self-check for ci/parse-spec.ps1. Run: pwsh ci/test-parse.ps1
#
# ci/test-parse.md has been the parser fixture since the beginning, but nothing ASSERTED against
# it. The README said "parse it and dry-run it - if the printed order, tiers or verify commands
# change, something broke", which makes a human the test. That is the same "ask someone whether
# it worked" failure the verify: contract exists to remove, so the fixture now has a harness.
#
# Everything here is free: no model, no network, no repo writes.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fails = 0
function Expect($name, $cond, $detail) {
  if ($cond) { Write-Host "ok   $name" } else { Write-Host "FAIL $name : $detail"; $script:fails++ }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("parsetest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# ---------------------------------------------------------------- the good fixture ----------
$out = Join-Path $tmp 'parsed.json'
pwsh (Join-Path $root 'ci/parse-spec.ps1') -Spec (Join-Path $root 'ci/test-parse.md') -Out $out | Out-Null
Expect 'fixture parses at all' ($LASTEXITCODE -eq 0) "parse-spec exited $LASTEXITCODE"
$p = Get-Content $out -Raw | ConvertFrom-Json
$byId = @{}; foreach ($t in $p.tasks) { $byId[$t.id] = $t }

Expect 'spec header read'   ($p.repo -eq 'aharger3/example' -and $p.version -eq 'selftest') "got $($p.repo) / $($p.version)"
Expect 'all five rows'      ($p.tasks.Count -eq 5)                    "got $($p.tasks.Count)"
Expect 'row order is spec order' ((($p.tasks | ForEach-Object { $_.id }) -join ',') -eq 'T1,T2,T3,T4,T5') 'rows reordered'

# ROUTING. The model: column is intent, and a silent change here is the expensive kind - it puts
# opus on mechanical work, which CLAUDE.md calls the most common review finding.
Expect 'T1 routes deepseek' ($byId.T1.model -eq 'deepseek')           "got $($byId.T1.model)"
Expect 'T2 routes opus'     ($byId.T2.model -eq 'opus')               "got $($byId.T2.model)"
Expect 'T3 keeps full glm tag' ($byId.T3.model -eq 'z-ai/glm-5.2')    "got $($byId.T3.model)"
Expect 'T5 routes glm'      ($byId.T5.model -eq 'glm')                "got $($byId.T5.model)"

# VERIFY, both dialects. The fenced-block one is the dangerous one: if it stops parsing, a
# two-command check silently becomes an empty string, and an empty check passes every row.
Expect 'inline verify'      ($byId.T1.verify -eq 'test -f README.md') "got [$($byId.T1.verify)]"
Expect 'verify keeps quotes' ($byId.T2.verify -eq 'grep -q "loop-ci" README.md') "got [$($byId.T2.verify)]"
Expect 'fenced verify keeps BOTH commands' ($byId.T3.verify -eq "test -d ci`ntest -f ci/notify.sh") "got [$($byId.T3.verify)]"
Expect 'no verify is ever empty on a pending row' (@($p.tasks | Where-Object { -not $_.done -and -not "$($_.verify)".Trim() }).Count -eq 0) 'a pending row parsed with an empty check'
# Backticks are markup; a glob inside them is part of the command. Clean() used to eat both.
Expect 'glob survives Clean()' ($byId.T5.verify -eq 'ls specs/*.md > /dev/null') "got [$($byId.T5.verify)]"

# DEPENDENCIES.
Expect 'T1 has no deps'     (@($byId.T1.dependsOn).Count -eq 0)       'T1 gained a dependency'
Expect 'T3 waits for T1'    ((@($byId.T3.dependsOn) -join ',') -eq 'T1') "got $($byId.T3.dependsOn -join ',')"
# `depends-on: everything` must expand to every OTHER row, including the [x] one, and must not
# name itself - a self-edge is an instant cycle and would throw in TopoOrder.
Expect 'everything expands'  ((@($byId.T5.dependsOn | Sort-Object) -join ',') -eq 'T1,T2,T3,T4') "got $($byId.T5.dependsOn -join ',')"
Expect 'everything excludes self' ($byId.T5.dependsOn -notcontains 'T5') 'T5 depends on itself'

# THE [x] ROW. It is skipped, and it is the one row allowed to carry no verify: at all.
Expect 'T4 is already done'  ($byId.T4.done -eq $true)                'the [x] row would be re-run'
Expect 'only T4 is done'     (@($p.tasks | Where-Object { $_.done }).Count -eq 1) 'wrong number of [x] rows'
Expect 'T4 needs no verify'  ("$($byId.T4.verify)".Trim() -eq '')     'the [x] row was made to carry a check'

# ---------------------------------------------------------------- what must be REJECTED -----
# Each of these cost a real run before it was caught. Rejection is at parse time, for zero
# tokens, and the exit code is what the workflow turns into the single BLOCKED notification.
function Reject($name, $body) {
  $f = Join-Path $tmp ("bad-" + [guid]::NewGuid().ToString('N') + '.md')
  $body | Set-Content $f
  pwsh (Join-Path $root 'ci/parse-spec.ps1') -Spec $f -Out (Join-Path $tmp 'x.json') 2>&1 | Out-Null
  Expect $name ($LASTEXITCODE -ne 0) 'parser ACCEPTED a spec it must refuse'
}

$hdr = "status: ready`nversion: bad`nrepo: aharger3/example`n`ntarget: t.`n`n## Tasks`n`n"
# The one that matters most: a pending row with no check. Reaching the runner, this row would
# have nothing to fail against.
Reject 'rejects pending row with no verify' ($hdr + "### T1 -- x`n- model: glm`n`nBody.`n`n- **done-when:** x`n")
Reject 'rejects row with no done-when'      ($hdr + "### T1 -- x`n- model: glm`n`nBody.`n`n- **verify:** ``true```n")
Reject 'rejects spec with no repo'          ("status: ready`nversion: bad`n`ntarget: t.`n`n## Tasks`n`n### T1 -- x`n- model: glm`n`nB.`n`n- **done-when:** x`n- **verify:** ``true```n")
Reject 'rejects void spec'                  (($hdr -replace 'status: ready','status: void') + "### T1 -- x`n- model: glm`n`nB.`n`n- **done-when:** x`n- **verify:** ``true```n")
Reject 'rejects dangling depends-on'        ($hdr + "### T1 -- x`n- model: glm`n- depends-on: T9`n`nB.`n`n- **done-when:** x`n- **verify:** ``true```n")
Reject 'rejects a spec with no rows'        ("status: ready`nversion: bad`nrepo: aharger3/example`n`ntarget: t.`n`n## Tasks`n")

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($fails) { Write-Host "`n$fails FAILED"; exit 1 }
Write-Host "`nall parse checks pass"

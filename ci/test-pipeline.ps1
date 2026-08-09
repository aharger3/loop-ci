# test-pipeline.ps1 - self-check for the two scripts that EDIT FILES: checkoff and vault-sync.
# Run: pwsh ci/test-pipeline.ps1
#
# Neither of these runs a model, and both munge markdown by hand, so they are exactly the kind
# of thing that breaks silently and is only noticed three runs later. Everything here works on
# throwaway copies in the temp dir - it never touches specs/ or a real vault.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fails = 0
function Expect($name, $cond, $detail) {
  if ($cond) { Write-Host "ok   $name" } else { Write-Host "FAIL $name : $detail"; $script:fails++ }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("looptest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# ---------------------------------------------------------------------- checkoff.ps1 --------
$spec = Join-Path $tmp 'demo.md'
@'
# demo

status: ready
version: demo-1.0
repo: aharger3/example

target: prove checkoff.

### T1 -- first row
- model: glm

Body.

- **done-when:** x
- **verify:** `true`

### T2 — em dash row, must still be matched
- model: glm

Body.

- **done-when:** x
- **verify:** `true`

### [x] T3 -- already done
- model: glm

Body.

- **done-when:** x
'@ | Set-Content $spec

$res = Join-Path $tmp 'result.json'
@{ version='demo-1.0'; done=1; total=2; tasks=@(
    @{ id='T1'; state='done' }, @{ id='T2'; state='failed' }, @{ id='T3'; state='skipped' }) } |
  ConvertTo-Json -Depth 6 | Set-Content $res

pwsh (Join-Path $root 'ci/checkoff.ps1') -Spec $spec -Result $res | Out-Null
$after = Get-Content $spec -Raw
Expect 'checkoff marks the verified row'    ($after -match '(?m)^### \[x\] T1 -- first row$')     'T1 not checked off'
Expect 'checkoff leaves the failed row'     ($after -match '(?m)^### T2 — em dash row')           'T2 was wrongly checked off'
Expect 'checkoff keeps the spec ready'      ($after -match '(?m)^status: ready$')                 'status flipped with a row still open'

# Second pass: now T2 passes too, so every row is [x] and the spec must retire itself. This is
# what stops a finished spec being re-selected forever by a blank workflow_dispatch.
@{ version='demo-1.0'; done=2; total=2; tasks=@(
    @{ id='T1'; state='done' }, @{ id='T2'; state='done' }) } |
  ConvertTo-Json -Depth 6 | Set-Content $res
pwsh (Join-Path $root 'ci/checkoff.ps1') -Spec $spec -Result $res | Out-Null
$after = Get-Content $spec -Raw
Expect 'checkoff marks the em-dash row'     ($after -match '(?m)^### \[x\] T2 — em dash row')     'em dash heading not rewritten'
Expect 'checkoff retires a finished spec'   ($after -match '(?m)^status: done$')                  'status should be done'

# It must be idempotent - a re-push of a finished spec must not double the [x] or throw.
pwsh (Join-Path $root 'ci/checkoff.ps1') -Spec $spec -Result $res | Out-Null
Expect 'checkoff is idempotent'             ((Select-String -Path $spec -Pattern '\[x\] T1').Count -eq 1) 'duplicated the marker'

# --------------------------------------------------------------------- vault-sync.ps1 -------
$vault = Join-Path $tmp 'vault'
New-Item -ItemType Directory -Force -Path (Join-Path $vault 'Projects') | Out-Null
$note = Join-Path $vault 'Projects/Demo.md'
@'
---
status: live
---

# Demo

## 🔬 Research

Some research.

## 🤖 Agent Questions

- [ ] an older question

## 💡 Agent Ideas

## Next build step

Do the thing.
'@ | Set-Content $note

$rdir = Join-Path $tmp 'results'
New-Item -ItemType Directory -Force -Path $rdir | Out-Null
@{ version='demo-1.0'; repo='aharger3/example'; doc='Projects/Demo.md'; done=1; total=2
   tasks=@(@{ id='T1'; state='done'; tier='glm'; note='wrote the thing' },
           @{ id='T2'; state='failed'; tier='opus'; note='verify failed (exit 1)' })
   questions=@(@{ id='T2'; text='which vendor for tick data?' })
   ideas=@(@{ id='T1'; text='reuse the enum' })
   humanTasks=@(@{ id='T2'; text='top up the polygon plan' }) } |
  ConvertTo-Json -Depth 6 | Set-Content (Join-Path $rdir 'result-demo.json')

pwsh (Join-Path $root 'ci/vault-sync.ps1') -Results $rdir -VaultDir $vault -DocOut (Join-Path $tmp 'doc.txt') | Out-Null
$n = Get-Content $note -Raw
Expect 'vault: run block written'      ($n -match '## Last loop run - demo-1\.0')            'no run block'
Expect 'vault: row table written'      ($n -match '\| T1 \| done \| glm \| wrote the thing \|') 'no row line'
Expect 'vault: question filed'         ($n -match 'which vendor for tick data\? — demo-1\.0 T2') 'question missing'
Expect 'vault: idea filed'             ($n -match 'reuse the enum — demo-1\.0 T1')           'idea missing'
Expect 'vault: old question kept'      ($n -match 'an older question')                       'clobbered existing content'
Expect 'vault: Next build step kept'   ($n -match '## Next build step')                      'ate a section'
# Human Tasks had no heading in this note - the content must be created, never dropped.
Expect 'vault: missing heading made'   ($n -match 'Human Tasks')                             'human task heading not created'
Expect 'vault: human task filed'       ($n -match 'top up the polygon plan')                 'human task missing'
Expect 'vault: doc path emitted'       ((Get-Content (Join-Path $tmp 'doc.txt') -Raw).Trim() -eq 'Projects/Demo.md') 'wrong DocOut'

# Re-run: the run block is REPLACED (never stacked) and the questions are NOT re-asked.
pwsh (Join-Path $root 'ci/vault-sync.ps1') -Results $rdir -VaultDir $vault -DocOut (Join-Path $tmp 'doc.txt') | Out-Null
$n = Get-Content $note -Raw
Expect 'vault: run block not stacked'  ((Select-String -Path $note -Pattern '## Last loop run - demo-1\.0').Count -eq 1) 'block duplicated'
Expect 'vault: question not repeated'  ((Select-String -Path $note -Pattern 'which vendor for tick data').Count -eq 1)   'question duplicated'
Expect 'vault: research survives'      ($n -match 'Some research\.')                          'lost the research section'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($fails) { Write-Host "`n$fails FAILED"; exit 1 }
Write-Host "`nall pipeline checks pass"

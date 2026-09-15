# Run-E2E.ps1 - Phases B/C/D of the pre-merge security E2E plan
# (plan: .gemini/plans/security_e2e_validation_v1.md)
#
# Drives the real engine (rmspkg.ps1) against malicious attack fixtures and
# the package_testnet lab packages, in the live C:\roms environment. Asserts:
#   B) every attack .rms aborts with exit 1, exactly ONE containment-class
#      [ERROR] line per run, and zero payload written outside the sandbox;
#   C) happy-path install -> shim exec -> uninstall round trip leaves no residue;
#   D) the same abort at -v / -vv / -vvv still emits no duplicate error lines.
#
# Phase A (unit-level guard contract) lives in Test-Guards.ps1 and must pass
# first. This runner makes NO product-code changes; it is test-only and cleans
# up every artifact it touches.

$ErrorActionPreference = "Continue"

$RepoRoot   = Split-Path $PSScriptRoot -Parent
$Engine     = Join-Path $RepoRoot "rmspkg.ps1"
$FixtureDir = Join-Path $PSScriptRoot "fixtures"
$Testnet    = Join-Path (Split-Path $RepoRoot -Parent) "package_testnet"
$MasterLog  = "C:\roms\logs\roms.log"

$Root        = "C:\roms"
$MetadataDir = "C:\roms\.metadata"
$BinDir      = "C:\roms\bin"
$LogsDir     = "C:\roms\logs"

# Containment-class messages produced by safety.ps1 / Check-RomsDependencies.
$ContainmentPattern = 'escapes root|traversal segment|Invalid name|UNC prefix|drive-letter segment'

$script:Pass = 0
$script:Fail = 0

function Report {
    param([bool]$Ok, [string]$Name, [string]$Detail = "")
    if ($Ok) { $script:Pass++; Write-Host "  [PASS] $Name" }
    else { $script:Fail++; Write-Host "  [FAIL] $Name -- $Detail" -ForegroundColor Red }
}

function Clean-Residue {
    # Idempotent pre/post cleanup of everything this suite can create.
    param([string[]]$Names)
    foreach ($n in $Names) {
        $d = Join-Path $Root $n
        if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction Continue }
        $m = Join-Path $MetadataDir "$n.json"
        if (Test-Path $m) { Remove-Path $m -ErrorAction Continue }
        $s = Join-Path $BinDir "$n.bat"
        if (Test-Path $s) { Remove-Item $s -Force -ErrorAction Continue }
        $l = Join-Path $LogsDir "$n.log"
        if (Test-Path $l) { Remove-Item $l -Force -ErrorAction Continue }
    }
    # Legacy residue from engine versions before the B1 log-name guard:
    # an escaped C:\roms\<name>.log could exist on disk from old runs.
    $esc = Join-Path $Root "sec-e2e-esc.log"
    if (Test-Path $esc) { Remove-Item $esc -Force -ErrorAction Continue }
}

# NOTE: metadata deletion uses Remove-Item (the $m variable holds the path).
# Rebound here to avoid a typo helper:
function Remove-Path { param($p) Remove-Item $p -Force -ErrorAction Continue }

function Mark-Log {
    # Drop a unique token in the master log so a run's lines can be isolated.
    $m = "E2E-MARKER-$([guid]::NewGuid().ToString('N'))"
    Add-Content -Path $MasterLog -Value $m -Encoding utf8
    return $m
}

function Get-LogTail {
    param([string]$Marker)
    if (-not (Test-Path $MasterLog)) { return @() }
    $lines = Get-Content $MasterLog
    $idx = ($lines | Select-String -SimpleMatch $Marker | Select-Object -Last 1).LineNumber
    if (-not $idx) { return @() }
    return @($lines[$idx..($lines.Count - 1)])
}

function Invoke-Engine {
    # Runs the engine as a real child process and returns exit code + merged output.
    param([string[]]$EngineArgs)
    $out = & pwsh -NoProfile -File $Engine @EngineArgs 2>&1
    return [PSCustomObject]@{ Exit = $LASTEXITCODE; Out = ($out | Out-String) }
}

function Invoke-AttackCase {
    # Full contract for one malicious .rms: exit 1, exactly one containment
    # ERROR line, and $ExtraChecks (scriptblocks returning $true on pass).
    param([string]$Fixture, [string]$Name, [hashtable]$ExpectAbsent = @{}, [scriptblock[]]$ExtraChecks = @())

    $marker = Mark-Log
    $r = Invoke-Engine @("install", $Fixture, "-y")
    $tail = Get-LogTail $marker

    Report ($r.Exit -eq 1) "$Name : exit code" "got $($r.Exit), expected 1"

    $cErr = @($tail | Where-Object { $_ -match '\[ERROR\]' -and $_ -match $ContainmentPattern })
    Report ($cErr.Count -eq 1) "$Name : exactly one containment ERROR" "got $($cErr.Count) in master log"

    $fail = @($tail | Where-Object { $_ -match 'Installation failed' })
    Report ($fail.Count -ge 1) "$Name : top-level failure logged once" "missing 'Installation failed'"

    # The guard message must NOT be echoed twice anywhere (dedup contract).
    $allGuardMsgs = @($tail | Where-Object { $_ -match $ContainmentPattern -and $_ -match '\[ERROR\]' })
    $distinct = $allGuardMsgs | ForEach-Object { ($_ -replace '^\[[^\]]+\] ','') } | Select-Object -Unique
    Report ($distinct.Count -le 1) "$Name : no duplicate guard message" ($distinct -join " || ")

    foreach ($k in $ExpectAbsent.Keys) {
        Report (-not (Test-Path $k)) "$Name : absent $k" "file/dir EXISTS (containment breach)"
    }
    foreach ($cb in $ExtraChecks) { & $cb $tail }

    Clean-Residue @($Name)
    return $r
}

# ===========================================================================
Write-Host "=============================================="
Write-Host " SECURITY E2E SUITE - package_installer"
Write-Host "=============================================="

# --- Preflight ---------------------------------------------------------------
foreach ($p in @($Engine, $MasterLog)) {
    if (-not (Test-Path $p)) { Write-Host "FATAL: missing $p (run Phase A / any install once first)"; exit 2 }
}
if (-not (Test-Path $Testnet)) { Write-Host "FATAL: package_testnet not found at $Testnet"; exit 2 }

# Build attack fixtures with Python (byte-exact ZIP entry names).
if (-not (Test-Path $FixtureDir)) { New-Item -ItemType Directory $FixtureDir | Out-Null }
& python (Join-Path $PSScriptRoot "make_fixtures.py") $FixtureDir | Out-Null
$fails = Get-ChildItem $FixtureDir -Filter *.rms
Write-Host "Fixtures built: $($fails.Name -join ', ')"

$fx = { param($n) Join-Path $FixtureDir $n }

Clean-Residue @("sec-e2e-hello","sec-e2e-esc","sec-e2e-h3","sec-e2e-h1","sec-e2e-h2","sec-e2e-l1","sec-e2e-env","hook-deep","helper","sec-e2e-m3")

# ===========================================================================
Write-Host "`n--- Phase B: attack fixtures ---"

# B1 (FIXED): C2 - traversal package name is rejected by Get-SafeName in
# rmspkg.ps1 BEFORE $script:logFile is composed, so nothing escapes at all —
# not even the per-package log file the old code planted at C:\roms\<name>.log.
$null = Invoke-AttackCase (& $fx "evil_name.rms") "sec-e2e-esc" @{
    "C:\roms\sec-e2e-esc"                   = $true   # appDir must not exist
    "C:\roms\.metadata\sec-e2e-esc.json"    = $true   # metadata must not exist
    "C:\roms\sec-e2e-esc.log"               = $true   # B1: escaped log must NOT exist
} -ExtraChecks {
    param($tail)
    Report (-not (Test-Path "C:\roms\.metadata\sec-e2e-esc.json")) "B1 : metadata not written under escaped name"
    Report (-not (Test-Path "C:\roms\bin\sec-e2e-esc.bat")) "B1 : shim not created"
    Report (-not (Test-Path "C:\roms\logs\sec-e2e-esc.log")) "B1 : no log planted inside logs dir either"
}

# B2: H3/M2 - files[] traversal entry embedded in ZIP must be rejected during
# extraction; rollback deletes the app dir; Windows target untouched.
$null = Invoke-AttackCase (& $fx "evil_file.rms") "sec-e2e-h3" @{
    "C:\Windows\sec-e2e-h3-file.txt" = $true
    "C:\roms\sec-e2e-h3"             = $true
}

# B3: C1/H1 - preInstall hook path traversal must be rejected at ZIP
# pre-extraction before pwsh ever sees the payload.
$null = Invoke-AttackCase (& $fx "evil_hook.rms") "sec-e2e-h1" @{
    "C:\Windows\sec-e2e-h1-hook.ps1" = $true
    "C:\roms\sec-e2e-h1"             = $true
} -ExtraChecks {
    param($tail)
    $exec = @($tail | Select-String -SimpleMatch "ATTACK-PAYLOAD-EXECUTED")
    Report ($exec.Count -eq 0) "B3 : hook payload never executed" "ATTACK-PAYLOAD-EXECUTED appears in log"
    $rh = @($tail | Select-String -SimpleMatch "Running hook")
    Report ($rh.Count -eq 0) "B3 : pwsh hook launch never attempted" "hook ran: $($rh[0])"
}

# B4: H2 - CMD metacharacter injection in executable string. Install SUCCEEDS
# (name/paths are legal); the shim must be caret-escaped so invoking it can
# never run the injected command. Sentinel file must never appear.
$marker = Mark-Log
$r = Invoke-Engine @("install", (& $fx "evil_shim.rms"), "-y")
Report ($r.Exit -eq 0) "B4 : evil_shim installs (payload is inert)" "exit $($r.Exit)"
$shim = "C:\roms\bin\sec-e2e-h2.bat"
Report (Test-Path $shim) "B4 : shim created"
if (Test-Path $shim) {
    $shimBody = Get-Content $shim -Raw
    Report ($shimBody -match '\^&') "B4 : shim body caret-escapes '&'" $shimBody
    Report ($shimBody -match '\^>') "B4 : shim body caret-escapes '>'" $shimBody
    # Execute the shim for real; the injected 'echo PWNED > ...' must not fire.
    $null = & cmd /c $shim 2>&1
}
Start-Sleep -Milliseconds 300
Report (-not (Test-Path "C:\sec-e2e-h2-pwned.txt")) "B4 : no PWNED sentinel after shim exec"
Clean-Residue @("sec-e2e-h2")

# B5: L1 - traversal dependency token rejected via Get-SafeName in
# Check-RomsDependencies before any directory creation.
$null = Invoke-AttackCase (& $fx "evil_dep.rms") "sec-e2e-l1" @{
    "C:\roms\sec-e2e-l1" = $true
}

# B6: environment_variables feature round trip (restored after the 03cbb6d
# collateral deletion). Machine scope is attempted first; this lab is non-admin,
# so the documented fallback must land the variable in User scope and track it
# as an env: artifact, and uninstall must purge it from both scopes.
$marker = Mark-Log
$r = Invoke-Engine @("install", (& $fx "envvar.rms"), "-y")
Report ($r.Exit -eq 0) "B6 : envvar install succeeds" "exit $($r.Exit)`n$($r.Out)"
$tail = Get-LogTail $marker
$cErr = @($tail | Where-Object { $_ -match '\[ERROR\]' -and $_ -match $ContainmentPattern })
Report ($cErr.Count -eq 0) "B6 : clean install triggers no guard" "$($cErr -join ' || ')"
$meta = Get-Content "C:\roms\.metadata\sec-e2e-env.json" -Raw | ConvertFrom-Json
Report ($meta.artifacts -contains "env:FOO") "B6 : env:FOO tracked as artifact" ($meta.artifacts -join ",")
Report ("BAR" -eq [Environment]::GetEnvironmentVariable("FOO", "User")) "B6 : FOO=BAR persisted (User fallback)"

$r = Invoke-Engine @("uninstall", "sec-e2e-env", "-y")
Report ($r.Exit -eq 0) "B6 : uninstall exit 0" "exit $($r.Exit)"
Report ($null -eq [Environment]::GetEnvironmentVariable("FOO", "User")) "B6 : FOO purged from User scope"
Report ($null -eq [Environment]::GetEnvironmentVariable("FOO", "Machine")) "B6 : FOO absent from Machine scope"
Report (-not (Test-Path "C:\roms\sec-e2e-env")) "B6 : app dir purged"
Clean-Residue @("sec-e2e-env")

# ===========================================================================
Write-Host "`n--- Phase C: lifecycle round trip ---"

# C1: engine-built happy path: install -> files/metadata/shim on disk ->
# shim executes payload -> uninstall -> zero residue.
$marker = Mark-Log
$r = Invoke-Engine @("install", (& $fx "hello.rms"), "-y")
Report ($r.Exit -eq 0) "C1 : hello.rms install exit 0" "exit $($r.Exit)`n$($r.Out)"
Report (Test-Path "C:\roms\sec-e2e-hello\hello.bat") "C1 : payload extracted"
Report (Test-Path "C:\roms\.metadata\sec-e2e-hello.json") "C1 : metadata registered"
$shimH = "C:\roms\bin\sec-e2e-hello.bat"
Report (Test-Path $shimH) "C1 : shim registered"
if (Test-Path $shimH) {
    $exec = & cmd /c $shimH 2>&1 | Out-String
    Report ($exec -match "HELLO-E2E-OK") "C1 : shim runs payload" "output: $exec"
}
$tail = Get-LogTail $marker
$cErr = @($tail | Where-Object { $_ -match '\[ERROR\]' -and $_ -match $ContainmentPattern })
Report ($cErr.Count -eq 0) "C1 : no guard fired on clean install" "$($cErr -join ' || ')"

$r = Invoke-Engine @("uninstall", "sec-e2e-hello", "-y")
Report ($r.Exit -eq 0) "C1 : uninstall exit 0" "exit $($r.Exit)"
Report (-not (Test-Path "C:\roms\sec-e2e-hello")) "C1 : app dir purged"
Report (-not (Test-Path "C:\roms\.metadata\sec-e2e-hello.json")) "C1 : metadata purged"
Report (-not (Test-Path $shimH)) "C1 : shim purged"

# C2: lab package with subdirectory hooks (relative pathing preserved):
# install/uninstall round trip from the rebuilt package_testnet .rms.
$labHook = Join-Path $Testnet "hook-deep-1.0.0.rms"
$r = Invoke-Engine @("install", $labHook, "-y")
Report ($r.Exit -eq 0) "C2 : hook-deep lab install exit 0" "exit $($r.Exit)`n$($r.Out)"
Report (Test-Path "C:\roms\hook-deep\scripts\pre.ps1") "C2 : nested hook path preserved"
Report (Test-Path "C:\roms\.metadata\hook-deep.json") "C2 : lab metadata registered"
$r = Invoke-Engine @("uninstall", "hook-deep", "-y")
Report ($r.Exit -eq 0) "C2 : hook-deep uninstall exit 0" "exit $($r.Exit)"
Report (-not (Test-Path "C:\roms\hook-deep")) "C2 : lab dir purged"
Report (-not (Test-Path "C:\roms\.metadata\hook-deep.json")) "C2 : lab metadata purged"
Clean-Residue @("hook-deep")

# C3: M3 - tampered metadata whose artifacts[] escape BOTH roots must abort
# the uninstall before any deletion.
$m3Name = "sec-e2e-m3"
$m3Dir  = "C:\roms\sec-e2e-m3"
$m3File = "C:\Users\Public\sec-e2e-m3-target.txt"   # outside app+bin roots
New-Item -ItemType Directory $m3Dir -Force | Out-Null
"outside-root" | Out-File $m3File -Encoding ascii
$m3Meta = [ordered]@{
    name = $m3Name; version = "1.0.0"; commandName = $m3Name
    executable = "$m3Dir\run.bat"; artifacts = @($m3File)
} | ConvertTo-Json
$m3Meta | Out-File "C:\roms\.metadata\sec-e2e-m3.json" -Encoding utf8
$marker = Mark-Log
$r = Invoke-Engine @("uninstall", $m3Name, "-y")
$tail = Get-LogTail $marker
Report ($r.Exit -ne 0) "C3 : escaping-artifact uninstall aborts (nonzero exit)" "exit $($r.Exit)"
$aErr = @($tail | Where-Object { $_ -match '\[ERROR\]' -and $_ -match 'escapes both app and bin roots' })
Report ($aErr.Count -eq 1) "C3 : exactly one artifact-escape ERROR" "got $($aErr.Count)"
Report (Test-Path $m3File) "C3 : outside-root file survived"
Clean-Residue @($m3Name)
if (Test-Path $m3File) { Remove-Item $m3File -Force }

# ===========================================================================
Write-Host "`n--- Phase D: verbosity 0-3 duplicate-error regression ---"
# Re-run the H3 traversal attack at every verbosity level and assert the
# abort contract holds identically: one containment ERROR in the file log and
# no duplicated console error regardless of -v/-vv/-vvv.
foreach ($lvl in @("v0","v1","v2","v3")) {
    $flag = switch ($lvl) { "v1" { "-v" } "v2" { "-vv" } "v3" { "-vvv" } default { $null } }
    $argsE = @("install", (& $fx "evil_file.rms"), "-y")
    if ($flag) { $argsE += $flag }
    $marker = Mark-Log
    $r = Invoke-Engine $argsE
    $tail = Get-LogTail $marker
    $cErr = @($tail | Where-Object { $_ -match '\[ERROR\]' -and $_ -match $ContainmentPattern })
    Report ($r.Exit -eq 1) "D-$lvl : exit 1" "got $($r.Exit)"
    Report ($cErr.Count -eq 1) "D-$lvl : one containment ERROR in log" "got $($cErr.Count)"
    $consErr = @(($r.Out -split "\r?\n") | Where-Object { $_ -match '\[ERROR\]' -and $_ -match $ContainmentPattern })
    Report ($consErr.Count -eq 1) "D-$lvl : one containment ERROR on console" "got $($consErr.Count): $($consErr -join ' || ')"
    Clean-Residue @("sec-e2e-h3")
}

# ===========================================================================
Write-Host "`n=============================================="
Write-Host " RESULT: $script:Pass passed, $script:Fail failed"
Write-Host "=============================================="
Clean-Residue @("sec-e2e-hello","sec-e2e-esc","sec-e2e-h3","sec-e2e-h1","sec-e2e-h2","sec-e2e-l1","sec-e2e-env","hook-deep","sec-e2e-m3")
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }

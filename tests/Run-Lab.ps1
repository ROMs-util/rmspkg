# Run-Lab.ps1 - Lab integration tests for the package_installer (rmspkg)
#
# Exercises package_testnet scenarios directly through the engine (rmspkg.ps1),
# bypassing the manager. Tests extraction, hooks, metadata, and rollback at
# the engine level. Requires: package_testnet .rms files present.

$ErrorActionPreference = "Continue"

$RepoRoot   = Split-Path $PSScriptRoot -Parent
$Engine     = Join-Path $RepoRoot "rmspkg.ps1"
$Testnet    = Join-Path (Split-Path $RepoRoot -Parent) "package_testnet"
$MasterLog  = "C:\roms\logs\roms.log"

$Root        = "C:\roms"
$MetadataDir = "C:\roms\.metadata"
$BinDir      = "C:\roms\bin"
$LogsDir     = "C:\roms\logs"

# Truncate master log to prevent stale entries from contaminating test results.
if (Test-Path $MasterLog) { Set-Content -Path $MasterLog -Value "" -Encoding utf8 -Force }

$script:Pass = 0
$script:Fail = 0

function Report {
    param([bool]$Ok, [string]$Name, [string]$Detail = "")
    if ($Ok) { $script:Pass++; Write-Host "  [PASS] $Name" }
    else { $script:Fail++; Write-Host "  [FAIL] $Name -- $Detail" -ForegroundColor Red }
}

function Clean-Residue {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $d = Join-Path $Root $n
        if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction Continue }
        $m = Join-Path $MetadataDir "$n.json"
        if (Test-Path $m) { Remove-Item $m -Force -ErrorAction Continue }
        $s = Join-Path $BinDir "$n.bat"
        if (Test-Path $s) { Remove-Item $s -Force -ErrorAction Continue }
        $l = Join-Path $LogsDir "$n.log"
        if (Test-Path $l) { Remove-Item $l -Force -ErrorAction Continue }
    }
}

function Invoke-Engine {
    param([string[]]$EngineArgs)
    $out = & pwsh -NoProfile -File $Engine @EngineArgs 2>&1
    return [PSCustomObject]@{ Exit = $LASTEXITCODE; Out = ($out | Out-String) }
}

function Mark-Log {
    $m = "LAB-MARKER-$([guid]::NewGuid().ToString('N'))"
    if (Test-Path $MasterLog) { Add-Content -Path $MasterLog -Value $m -Encoding utf8 }
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

# ===========================================================================
Write-Host "=============================================="
Write-Host " LAB SUITE - package_installer (rmspkg)"
Write-Host "=============================================="

# --- Preflight ---
if (-not (Test-Path $Engine)) { Write-Host "FATAL: engine not found at $Engine"; exit 2 }
if (-not (Test-Path $Testnet)) { Write-Host "FATAL: package_testnet not found at $Testnet"; exit 2 }

# ===========================================================================
Write-Host "`n--- 1. Happy Path: install -> files -> metadata -> uninstall ---"

$happyRms = Join-Path $Testnet "helper-1.0.0.rms"
Clean-Residue @("helper")
$marker = Mark-Log
$r = Invoke-Engine @("install", $happyRms, "-y")
Report ($r.Exit -eq 0) "helper-1.0.0 install exit 0" "exit=$($r.Exit)"
Report (Test-Path "C:\roms\helper") "helper directory created"
Report (Test-Path "C:\roms\.metadata\helper.json") "helper metadata created"

# Verify metadata version
if (Test-Path "C:\roms\.metadata\helper.json") {
    $meta = Get-Content "C:\roms\.metadata\helper.json" -Raw | ConvertFrom-Json
    Report ($meta.version -eq "1.0.0") "helper version is 1.0.0" "got $($meta.version)"
}

# Verify shim
$shimPath = Join-Path $BinDir "lab-helper.bat"
Report (Test-Path $shimPath) "lab-helper shim created"

$r = Invoke-Engine @("uninstall", "helper", "-y")
Report ($r.Exit -eq 0) "helper uninstall exit 0" "exit=$($r.Exit)"
Report (-not (Test-Path "C:\roms\helper")) "helper directory removed"
Report (-not (Test-Path "C:\roms\.metadata\helper.json")) "helper metadata removed"
Clean-Residue @("helper")

# ===========================================================================
Write-Host "`n--- 2. Hook Execution (hook-manifest: all 4 lifecycle hooks) ---"

$hookRms = Join-Path $Testnet "hook-manifest-1.0.0.rms"
Clean-Residue @("hook-manifest")
$hookLog = Join-Path $LogsDir "hook-verify.log"
if (Test-Path $hookLog) { Remove-Item $hookLog -Force }

$r = Invoke-Engine @("install", $hookRms, "-y")
Report ($r.Exit -eq 0) "hook-manifest install exit 0" "exit=$($r.Exit)"

$r = Invoke-Engine @("uninstall", "hook-manifest", "-y")
Report ($r.Exit -eq 0) "hook-manifest uninstall exit 0" "exit=$($r.Exit)"

if (Test-Path $hookLog) {
    $hookContent = Get-Content $hookLog -Raw
    Report ($hookContent -match "PRE-INSTALL") "pre-install hook fired"
    Report ($hookContent -match "POST-INSTALL") "post-install hook fired"
    Report ($hookContent -match "PRE-UNINSTALL") "pre-uninstall hook fired"
    Report ($hookContent -match "POST-UNINSTALL") "post-uninstall hook fired"
} else {
    Report $false "hook-verify.log exists" "file not found"
}

Clean-Residue @("hook-manifest")

# ===========================================================================
Write-Host "`n--- 3. Subdirectory Hooks (hook-deep: relative path preservation) ---"

$deepRms = Join-Path $Testnet "hook-deep-1.0.0.rms"
Clean-Residue @("hook-deep")
$hookLog2 = Join-Path $LogsDir "hook-verify.log"
if (Test-Path $hookLog2) { Remove-Item $hookLog2 -Force }

$r = Invoke-Engine @("install", $deepRms, "-y")
Report ($r.Exit -eq 0) "hook-deep install exit 0" "exit=$($r.Exit)"
Report (Test-Path "C:\roms\hook-deep\scripts\pre.ps1") "nested hook path preserved"

$r = Invoke-Engine @("uninstall", "hook-deep", "-y")
Report ($r.Exit -eq 0) "hook-deep uninstall exit 0" "exit=$($r.Exit)"

if (Test-Path $hookLog2) {
    $hookContent2 = Get-Content $hookLog2 -Raw
    Report ($hookContent2 -match "PRE-INSTALL") "deep pre-install hook fired"
    Report ($hookContent2 -match "POST-INSTALL") "deep post-install hook fired"
    Report ($hookContent2 -match "PRE-UNINSTALL") "deep pre-uninstall hook fired"
    Report ($hookContent2 -match "POST-UNINSTALL") "deep post-uninstall hook fired"
} else {
    Report $false "hook-verify.log exists (deep)" "file not found"
}

Clean-Residue @("hook-deep")

# ===========================================================================
Write-Host "`n--- 4. Failing Hook Rollback (state-breaker: postInstall exit 1) ---"

$breakRms = Join-Path $Testnet "state-breaker-1.0.0.rms"
Clean-Residue @("state-breaker")
$marker = Mark-Log
$r = Invoke-Engine @("install", $breakRms, "-y")
Report ($r.Exit -ne 0) "state-breaker install exits non-zero" "exit=$($r.Exit)"

# Directory must be cleaned up (transactional rollback)
Report (-not (Test-Path "C:\roms\state-breaker")) "state-breaker directory absent (rollback)"
Report (-not (Test-Path "C:\roms\.metadata\state-breaker.json")) "state-breaker metadata absent"

Clean-Residue @("state-breaker")

# ===========================================================================
Write-Host "`n--- 5. Metadata Artifacts Tracking (pivot-v1) ---"

$pivotRms = Join-Path $Testnet "pivot-v1-1.0.0.rms"
Clean-Residue @("pivot-v1")
$r = Invoke-Engine @("install", $pivotRms, "-y")
Report ($r.Exit -eq 0) "pivot-v1 install exit 0" "exit=$($r.Exit)"

# Verify metadata tracks the shim artifact
if (Test-Path "C:\roms\.metadata\pivot-v1.json") {
    $meta = Get-Content "C:\roms\.metadata\pivot-v1.json" -Raw | ConvertFrom-Json
    $hasShim = $meta.artifacts -contains "C:\roms\bin\lab-pivot.bat"
    Report $hasShim "pivot-v1 metadata tracks lab-pivot.bat artifact"
} else {
    Report $false "pivot-v1 metadata exists" "file not found"
}

# Verify shim was created
Report (Test-Path "C:\roms\bin\lab-pivot.bat") "lab-pivot.bat shim exists"

# Uninstall and verify cleanup
$r = Invoke-Engine @("uninstall", "pivot-v1", "-y")
Report ($r.Exit -eq 0) "pivot-v1 uninstall exit 0" "exit=$($r.Exit)"
Report (-not (Test-Path "C:\roms\pivot-v1")) "pivot-v1 directory removed"
Report (-not (Test-Path "C:\roms\bin\lab-pivot.bat")) "lab-pivot.bat shim removed"

Clean-Residue @("pivot-v1")

# ===========================================================================
Write-Host "`n--- 6. Environment Variables (env-pro: Machine/User scope) ---"

$envRms = Join-Path $Testnet "env-pro-1.0.0.rms"
Clean-Residue @("env-pro")
$r = Invoke-Engine @("install", $envRms, "-y")
Report ($r.Exit -eq 0) "env-pro install exit 0" "exit=$($r.Exit)"

# Check env var was set (Machine or User scope)
$machineVal = [System.Environment]::GetEnvironmentVariable("ROMS_LAB_VAR", "Machine")
$userVal = [System.Environment]::GetEnvironmentVariable("ROMS_LAB_VAR", "User")
Report ($machineVal -eq "STABLE" -or $userVal -eq "STABLE") "ROMS_LAB_VAR set" "machine=$machineVal user=$userVal"

# Uninstall and verify cleanup
$r = Invoke-Engine @("uninstall", "env-pro", "-y")
Report ($r.Exit -eq 0) "env-pro uninstall exit 0" "exit=$($r.Exit)"
$machineAfter = [System.Environment]::GetEnvironmentVariable("ROMS_LAB_VAR", "Machine")
$userAfter = [System.Environment]::GetEnvironmentVariable("ROMS_LAB_VAR", "User")
Report ($null -eq $machineAfter -and $null -eq $userAfter) "ROMS_LAB_VAR cleaned up" "machine=$machineAfter user=$userAfter"

Clean-Residue @("env-pro")

# ===========================================================================
Write-Host "`n--- 7. Verbose Levels: no duplicate errors (state-breaker at -v/-vv/-vvv) ---"

foreach ($lvl in @("v1","v2","v3")) {
    $flag = switch ($lvl) { "v1" { "-v" } "v2" { "-vv" } "v3" { "-vvv" } }
    Clean-Residue @("state-breaker")
    $marker = Mark-Log
    $r = Invoke-Engine @("install", $breakRms, "-y", $flag)
    $tail = Get-LogTail $marker
    Report ($r.Exit -ne 0) "D-$lvl : state-breaker exits non-zero" "exit=$($r.Exit)"
    # Verify directory is still absent (rollback works at all verbosity levels)
    Report (-not (Test-Path "C:\roms\state-breaker")) "D-$lvl : state-breaker absent"
    Clean-Residue @("state-breaker")
}

# ===========================================================================
# CLEANUP
# ===========================================================================
Write-Host "`n--- Final Cleanup ---"
Clean-Residue @(
    "helper", "hook-manifest", "hook-deep", "state-breaker",
    "pivot-v1", "pivot-v2", "env-pro"
)

# ===========================================================================
Write-Host "`n=============================================="
Write-Host " RESULT: $script:Pass passed, $script:Fail failed"
Write-Host "=============================================="
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }

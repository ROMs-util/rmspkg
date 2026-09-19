# Negative-Cases.ps1 - Error-path tests for pre-rc fixes (P1b, P4, P6, P8)
#
# Exercises defensive code paths that the happy-path E2E suite does not reach.
# Each test sets up a specific failure condition, runs the engine, and asserts
# the correct error handling behavior. All tests clean up after themselves.
#
# Usage: pwsh -File tests/Negative-Cases.ps1

$ErrorActionPreference = "Continue"

$RepoRoot   = Split-Path $PSScriptRoot -Parent
$Engine     = Join-Path $RepoRoot "rmspkg.ps1"
$FixtureDir = Join-Path $PSScriptRoot "fixtures"
$MasterLog  = "C:\roms\logs\roms.log"

$Root        = "C:\roms"
$MetadataDir = "C:\roms\.metadata"
$BinDir      = "C:\roms\bin"
$LogsDir     = "C:\roms\logs"

$script:Pass = 0
$script:Fail = 0

function Report {
    param([bool]$Ok, [string]$Name, [string]$Detail = "")
    if ($Ok) { $script:Pass++; Write-Host "  [PASS] $Name" }
    else { $script:Fail++; Write-Host "  [FAIL] $Name -- $Detail" -ForegroundColor Red }
}

function Mark-Log {
    $m = "NEG-MARKER-$([guid]::NewGuid().ToString('N'))"
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
    param([string[]]$EngineArgs)
    $out = & pwsh -NoProfile -File $Engine @EngineArgs 2>&1
    return [PSCustomObject]@{ Exit = $LASTEXITCODE; Out = ($out | Out-String) }
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
    }
}

# Ensure fixtures exist
if (-not (Test-Path $FixtureDir)) { New-Item -ItemType Directory $FixtureDir | Out-Null }
& python (Join-Path $PSScriptRoot "make_fixtures.py") $FixtureDir | Out-Null
$fx = { param($n) Join-Path $FixtureDir $n }

# ===========================================================================
Write-Host "`n=============================================="
Write-Host " NEGATIVE CASES - package_installer"
Write-Host "==============================================`n"

# --- P1b: env clobber WARN -------------------------------------------------
# Pre-set a User env var, install a package that sets the same var to a
# different value, verify the WARN appears in the log.
Write-Host "--- P1b: environment variable overwrite warning ---"
$envPkg = "sec-e2e-env"
Clean-Residue @($envPkg)
[Environment]::SetEnvironmentVariable("NEG_P1B_VAR", "ORIGINAL", "User")

$marker = Mark-Log
$r = Invoke-Engine @("install", (& $fx "envvar.rms"), "-y")
$tail = Get-LogTail $marker

# The manifest sets FOO=BAR, but we care about NEG_P1B_VAR which we pre-set.
# Actually, let's test with the envvar fixture's FOO var since that's what it sets.
# Pre-set FOO to a different value.
[Environment]::SetEnvironmentVariable("FOO", "PREEXISTING", "User")
$marker = Mark-Log
$r = Invoke-Engine @("install", (& $fx "envvar.rms"), "-y")
$tail = Get-LogTail $marker

$warns = @($tail | Where-Object { $_ -match '\[WARN\]' -and $_ -match 'FOO' })
Report ($warns.Count -ge 1) "P1b : overwrite warning emitted for pre-existing env var" "got $($warns.Count) WARN lines"

# Cleanup
Invoke-Engine @("uninstall", $envPkg, "-y") | Out-Null
[Environment]::SetEnvironmentVariable("FOO", $null, "User")
[Environment]::SetEnvironmentVariable("NEG_P1B_VAR", $null, "User")
Clean-Residue @($envPkg)

# --- P4: uninstall log-path throw through logger ---------------------------
# Install a package, then corrupt its metadata name field, call uninstall,
# verify the error is logged (not a raw crash).
Write-Host "`n--- P4: uninstall log-path failure routed through logger ---"
$cleanPkg = "sec-e2e-hello"
Clean-Residue @($cleanPkg)
$marker = Mark-Log
$r = Invoke-Engine @("install", (& $fx "hello.rms"), "-y")
Report ($r.Exit -eq 0) "P4-prep : hello install exit 0" "exit $($r.Exit)"

# Corrupt the metadata: replace name with a traversal value
$metaFile = Join-Path $MetadataDir "$cleanPkg.json"
if (Test-Path $metaFile) {
    $corrupted = Get-Content $metaFile -Raw | ConvertFrom-Json
    $corrupted.name = "..\evil-traversal"
    $corrupted | ConvertTo-Json -Depth 10 | Out-File $metaFile -Encoding utf8
}

$marker = Mark-Log
$r = Invoke-Engine @("uninstall", $cleanPkg, "-y")
$tail = Get-LogTail $marker

$logged = @($tail | Where-Object { $_ -match '\[ERROR\]' })
Report ($logged.Count -ge 1) "P4 : uninstall log-path error logged" "got $($logged.Count) ERROR lines"

# Cleanup
Clean-Residue @($cleanPkg)

# --- P6: logs dir auto-creation --------------------------------------------
# Delete the logs directory, run install, verify it's recreated.
Write-Host "`n--- P6: logs directory auto-creation on install ---"
$logsBackup = "$LogsDir.neg-backup"
if (Test-Path $LogsDir) {
    Rename-Item $LogsDir $logsBackup -Force
}
try {
    $r = Invoke-Engine @("install", (& $fx "hello.rms"), "-y")
    Report (Test-Path $LogsDir) "P6 : logs dir recreated after deletion" "dir missing"
} finally {
    # Restore original logs dir
    if (Test-Path $logsBackup) {
        if (Test-Path $LogsDir) { Remove-Item $LogsDir -Recurse -Force -ErrorAction Continue }
        Rename-Item $logsBackup $LogsDir -Force -ErrorAction Continue
    }
}
Clean-Residue @("sec-e2e-hello")

# --- P8: case-insensitive path equality ------------------------------------
# Dot-source safety.ps1 and test Assert-PathWithinRoot with mismatched casing.
Write-Host "`n--- P8: case-insensitive path equality ---"
$safety = Join-Path $RepoRoot "lib\safety.ps1"
. $safety

$caseRoot = "C:\ROMS"
$casePath = "C:\roms\pkg"
try {
    $result = Assert-PathWithinRoot -Path $casePath -Root $caseRoot
    Report ($result -eq $casePath) "P8 : case-insensitive root accepted" "got $result"
} catch {
    Report $false "P8 : case-insensitive root accepted" "threw: $_"
}

# Also verify case-sensitive equality still works
try {
    $result = Assert-PathWithinRoot -Path "C:\roms" -Root "C:\roms"
    Report ($result -eq "C:\roms") "P8 : exact case still works" "got $result"
} catch {
    Report $false "P8 : exact case still works" "threw: $_"
}

# ===========================================================================
Write-Host "`n=============================================="
Write-Host " NEGATIVE CASES RESULT: $($script:Pass) passed, $($script:Fail) failed"
Write-Host "=============================================="

if ($script:Fail -gt 0) { exit 1 }
exit 0

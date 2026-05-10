param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$packagePath,

    [Parameter(Mandatory = $false)]
    [string]$config,

    [Parameter(Mandatory = $false)]
    [switch]$uninstall,

    [Parameter(Mandatory = $false)]
    [switch]$help,

    [switch]$installEngine,
    [switch]$skipAdvice
)

# ---------------------------------------------
# LOAD MODULES (Dot-Sourcing)
# ---------------------------------------------
$libPath = Join-Path $PSScriptRoot "lib"
. (Join-Path $libPath "core.ps1")
. (Join-Path $libPath "help.ps1")
. (Join-Path $libPath "environment.ps1")
. (Join-Path $libPath "installer.ps1")
. (Join-Path $libPath "uninstaller.ps1")

# ---------------------------------------------
# PRE-FLIGHT CHECKS (NON-ADMIN)
# ---------------------------------------------
if ($help -or (-not $packagePath -and -not $config -and -not $uninstall)) {
    $invokedAs = if ($PSScriptRoot -notlike "*C:\roms*") { ".\rmspkg.bat" } else { "rmspkg" }
    Show-Help -invokedAs $invokedAs
    exit 0
}

# Resolve Paths
if ($packagePath) { $packagePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $packagePath)) }
if ($config)      { $config = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $config)) }

# Discovery Identity
$packageConfig = $null
$isRmsPackage  = $false

if ($config -and (Test-Path $config)) {
    $packageConfig = Get-Content $config -Raw | ConvertFrom-Json
} elseif ($packagePath) {
    if (Test-Path $packagePath -PathType Leaf) {
        if ($packagePath.EndsWith(".rms", [System.StringComparison]::OrdinalIgnoreCase)) {
            $isRmsPackage = $true
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            try {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
                $entry = $zip.Entries | Where-Object { $_.FullName -eq "roms_package.json" }
                if ($entry) {
                    $temp = Join-Path $env:TEMP "rmspkg_peek_$([guid]::NewGuid().ToString()).json"
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $temp)
                    $packageConfig = Get-Content $temp -Raw | ConvertFrom-Json
                    Remove-Item $temp
                }
                $zip.Dispose()
            } catch { if ($zip) { $zip.Dispose() } }
        }
    } elseif (Test-Path $packagePath -PathType Container) {
        $localJson = Join-Path $packagePath "roms_package.json"
        if (Test-Path $localJson) { $packageConfig = Get-Content $localJson -Raw | ConvertFrom-Json }
    }
} elseif ($uninstall) {
    $localJson = Join-Path (Get-Location).Path "roms_package.json"
    if (Test-Path $localJson) { $packageConfig = Get-Content $localJson -Raw | ConvertFrom-Json }
}

$commandName = if ($packageConfig -and $packageConfig.commandName) { $packageConfig.commandName } else { "unknown" }

# ---------------------------------------------
# ADVICE & ELEVATION
# ---------------------------------------------
$finalInstallEngine = $installEngine
if (-not $skipAdvice -and -not (Test-Path $engineDir) -and -not (Test-Path $engineShim) -and ($PSScriptRoot -ne $engineDir)) {
    Write-Host "`nADVICE: rmspkg is running in portable mode." -ForegroundColor Yellow
    Write-Host "Would you like to install it permanently to $engineDir?"
    Write-Host "This will also register 'rmspkg' as a global command."
    $choice = Read-Host "Install rmspkg globally? (y/n)"
    if ($choice.Trim().ToLower() -eq "y") { $finalInstallEngine = $true }
}

# Elevation Check
$params = @{ packagePath=$packagePath; config=$config; uninstall=$uninstall; installEngine=$finalInstallEngine }
if (-not (Confirm-Elevation -cmdPath $PSCommandPath -params $params)) { exit 0 }

# ---------------------------------------------
# EXECUTION (NOW ELEVATED)
# ---------------------------------------------

# Initialize System
@($systemRoot, $metadataRoot, $logRoot, $binRoot) | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null; if ($_ -eq $metadataRoot) { (Get-Item $_).Attributes = "Hidden" } } }

# Environment Setup
Update-EnvironmentPath
Invoke-SelfBootstrap -finalInstallEngine $finalInstallEngine -scriptRoot $PSScriptRoot -engineDir $engineDir -engineShimPath $engineShim

# Action Routing
if ($uninstall) {
    Invoke-Uninstallation -packageConfig $packageConfig
} else {
    $logFile = Join-Path $logRoot "$commandName.log"
    Write-Log "Starting modular installation for $commandName"
    try {
        Invoke-Installation -packageConfig $packageConfig -isRmsPackage $isRmsPackage -packagePath $packagePath -sourceDir (Split-Path $PSCommandPath)
    } catch {
        Write-Error "[FATAL] Modular Installation failed. See log: $logFile"
        exit 1
    }
}

Write-Host "`n-----------------------------------------------------"
Write-Host "[SUCCESS] Operation finished for $commandName."
Write-Host "-----------------------------------------------------`n"

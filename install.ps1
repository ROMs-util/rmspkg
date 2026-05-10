param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$packagePath,

    [Parameter(Mandatory = $false)]
    [string]$config,

    [Parameter(Mandatory = $false)]
    [switch]$uninstall,

    [Parameter(Mandatory = $false)]
    [switch]$help,

    # Internal parameters for decision passing
    [switch]$installEngine,
    [switch]$skipAdvice
)

# ---------------------------------------------
# HELP SYSTEM (FUNCTIONAL & COLORIZED)
# ---------------------------------------------
function Show-Help {
    # Dynamic Command Name Detection
    $invokedAs = "rmspkg"
    if ($PSScriptRoot -notlike "*C:\roms*") { $invokedAs = ".\rmspkg.bat" }

    Write-Host ""
    Write-Host "----- rmspkg : ROMs Package Engine -----" -ForegroundColor Cyan
    Write-Host "The official standalone engine for the .rms ecosystem."
    Write-Host ""
    
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  $invokedAs <path> [options]"
    Write-Host ""

    Write-Host "OPTIONS:" -ForegroundColor Yellow
    Write-Host "  <path>             Path to an .rms file or a local project folder."
    Write-Host "  -config <path>     Manually specify a roms_package.json location."
    Write-Host "  --uninstall        Switch to uninstallation mode."
    Write-Host "  --help             Show this menu."
    Write-Host ""

    Write-Host "SYSTEM PATHS:" -ForegroundColor Yellow
    Write-Host "  Root:    C:\roms"
    Write-Host "  Bin:     C:\roms\bin (Command Launchers)"
    Write-Host "  Logs:    C:\roms\logs"
    Write-Host ""

    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  Install:   $invokedAs .\myapp.rms"
    Write-Host "  Local:     $invokedAs .\my-project-folder"
    Write-Host "  Cleanup:   $invokedAs -config C:\roms\.metadata\app.json --uninstall"
    Write-Host ""
    
    Write-Host "Note: Administrator privileges are only required for installation/removal."
    Write-Host "-----------------------------------------------------"
    Write-Host ""
}

if ($help -or (-not $packagePath -and -not $config -and -not $uninstall)) {
    Show-Help
    exit 0
}

# ---------------------------------------------
# PATH RESOLUTION & EARLY MANIFEST DISCOVERY
# ---------------------------------------------
if ($packagePath) {
    $packagePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $packagePath))
}
if ($config) {
    $config = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $config))
}

$packageConfig = $null
$isRmsPackage  = $false

# PEER INTO PACKAGE TO GET IDENTITY (Early)
if ($config -and (Test-Path $config)) {
    $packageConfig = Get-Content $config -Raw | ConvertFrom-Json
} elseif ($packagePath) {
    if (Test-Path $packagePath -PathType Leaf) {
        if ($packagePath.EndsWith(".rms", [System.StringComparison]::OrdinalIgnoreCase)) {
            $isRmsPackage = $true
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            try {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
                $manifestEntry = $zip.Entries | Where-Object { $_.FullName -eq "roms_package.json" }
                if ($manifestEntry) {
                    $temp = Join-Path $env:TEMP "rmspkg_peek_$([guid]::NewGuid().ToString()).json"
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($manifestEntry, $temp)
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

$commandName = "unknown"
if ($packageConfig -and $packageConfig.commandName) { $commandName = $packageConfig.commandName }

# ---------------------------------------------
# SETUP SYSTEM ROOT (READ-ONLY PRE-CHECK)
# ---------------------------------------------
$systemRoot   = "C:\roms"
$metadataRoot = Join-Path $systemRoot ".metadata"
$logRoot      = Join-Path $systemRoot "logs"
$binRoot      = Join-Path $systemRoot "bin"
$engineDir    = Join-Path $systemRoot "rmspkg"
$engineShim   = Join-Path $binRoot "rmspkg.bat"

# ---------------------------------------------
# STANDALONE ENGINE ADVICE (STRICT OPT-IN)
# ---------------------------------------------
$finalInstallEngine = $installEngine
if (-not $skipAdvice -and -not (Test-Path $engineDir) -and -not (Test-Path $engineShim) -and ($PSScriptRoot -ne $engineDir)) {
    Write-Host ""
    Write-Host "ADVICE: rmspkg is running in portable mode." -ForegroundColor Yellow
    Write-Host "Would you like to install it permanently to $engineDir?"
    Write-Host "This will also register 'rmspkg' as a global command."
    $choice = Read-Host "Install rmspkg globally? (y/n)"
    if ($choice.Trim().ToLower() -eq "y") { $finalInstallEngine = $true }
    else { Write-Host "[INFO] Staying portable. No system shims created for the engine." }
}

# ---------------------------------------------
# ELEVATION CHECK (SURGICAL RELAUNCH)
# ---------------------------------------------
$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argString = "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($packagePath) { $argString += " `"$packagePath`"" }
    if ($config)      { $argString += " -config `"$config`"" }
    if ($uninstall)   { $argString += " -uninstall" }
    if ($finalInstallEngine) { $argString += " -installEngine" }
    $argString += " -skipAdvice" 
    
    Start-Process powershell -Verb RunAs -ArgumentList $argString
    exit 0
}

# ---------------------------------------------
# GLOBALS & UTILITIES (NOW ELEVATED)
# ---------------------------------------------
$tempDir   = $null
$globalArtifacts = @()

# Ensure directories exist
@($systemRoot, $metadataRoot, $logRoot, $binRoot) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ | Out-Null
        if ($_ -eq $metadataRoot) { (Get-Item $_).Attributes = "Hidden" }
    }
}

function Write-Log {
    param([string]$message, [string]$level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$level] $message"
    Write-Host $logEntry
    if ($logFile) { $logEntry | Out-File -FilePath $logFile -Append -Encoding utf8 }
}

function Create-Shim {
    param([string]$name, [string]$execPath)
    $shimPath = Join-Path $binRoot "$name.bat"
    $content = if ($execPath.EndsWith(".ps1")) { "@echo off`npowershell -ExecutionPolicy Bypass -File `"$execPath`" %*" }
               else { "@echo off`ncall `"$execPath`" %*" }
    $content | Out-File -FilePath $shimPath -Encoding ascii
    Write-Log "Created shim: $name -> $execPath"
    if ($global:globalArtifacts -notcontains $shimPath) { $global:globalArtifacts += $shimPath }
}

function Update-EnvironmentPath {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not (($currentPath -split ";") -contains $binRoot)) {
        Write-Log "Adding $binRoot to User PATH..."
        [Environment]::SetEnvironmentVariable("PATH", $currentPath + ";" + $binRoot, "User")
        Write-Host "[PATH] Added $binRoot to User PATH. Restart terminal to apply."
    }
}

function Check-RomsDependencies {
    param($dependencies)
    if ($null -eq $dependencies -or $null -eq $dependencies.roms) { return }
    foreach ($depName in $dependencies.roms) {
        if (-not (Test-Path (Join-Path $metadataRoot "$depName.json"))) {
            throw "Missing required package dependency: '$depName'. Please install it first."
        }
        Write-Log "Verified dependency: $depName"
    }
}

# ---------------------------------------------
# UNINSTALL MODE
# ---------------------------------------------
if ($uninstall) {
    if (-not $packageConfig) { Write-Error "No package configuration found to uninstall."; exit 1 }
    $logFile = Join-Path $logRoot "$commandName.log"
    Write-Log "-----------------------------------------------------"
    Write-Log "rmspkg uninstall - $commandName"

    $confirm = Read-Host "This will delete $($packageConfig.installDir) and all tracked shims. Proceed? (y/n)"
    if ($confirm.Trim().ToLower() -ne "y") { Write-Log "[ABORTED] Cancelled."; exit 0 }

    $hook = Join-Path $packageConfig.installDir "rms_uninstall.ps1"
    if (Test-Path $hook) { Write-Log "Running uninstall hook..."; & $hook 2>&1 | ForEach-Object { Write-Log "  [HOOK] $_" } }

    if ($packageConfig.artifacts) {
        foreach ($art in $packageConfig.artifacts) {
            if (Test-Path $art -PathType Leaf) { Remove-Item $art -Force; Write-Log "Removed artifact: $art" }
        }
    }

    if (Test-Path $packageConfig.installDir) { Remove-Item -Path $packageConfig.installDir -Recurse -Force; Write-Log "Deleted: $($packageConfig.installDir)" }
    $meta = Join-Path $metadataRoot "$commandName.json"
    if (Test-Path $meta) { Remove-Item $meta -Force; Write-Log "Unregistered from database." }

    Write-Log "rmspkg: $commandName uninstalled successfully."
    Write-Log "-----------------------------------------------------"
    exit 0
}

# ---------------------------------------------
# INSTALL MODE
# ---------------------------------------------
Write-Host ""
Write-Host "rmspkg install - $commandName"
Write-Host "-----------------------------------------------------"

Update-EnvironmentPath

# SELF-BOOTSTRAP
if ($finalInstallEngine -or ($PSScriptRoot -eq $engineDir)) {
    if (-not (Test-Path $engineDir)) { New-Item -ItemType Directory -Path $engineDir -Force | Out-Null }
    if ($PSScriptRoot -ne $engineDir) {
        Write-Log "Installing rmspkg engine to system root..."
        Copy-Item (Join-Path $PSScriptRoot "install.ps1") (Join-Path $engineDir "install.ps1") -Force
        $engineManifest = Join-Path $PSScriptRoot "roms_package.json"
        if (Test-Path $engineManifest) { Copy-Item $engineManifest (Join-Path $engineDir "roms_package.json") -Force }
    }

    if ($finalInstallEngine -or -not (Test-Path $engineShim)) {
        if (-not (Test-Path $engineShim)) { Create-Shim "rmspkg" (Join-Path $engineDir "install.ps1") }
        $localManifest = Join-Path $engineDir "roms_package.json"
        if (Test-Path $localManifest) {
            $eConfig = Get-Content $localManifest -Raw | ConvertFrom-Json
            $eConfig | Add-Member -MemberType NoteProperty -Name "artifacts" -Value @($engineShim) -Force
            $eConfig | ConvertTo-Json -Depth 10 | Out-File (Join-Path $metadataRoot "rmspkg.json") -Encoding utf8
            Write-Log "Engine registered in metadata database"
        }
        $global:globalArtifacts = @() # Reset for app
        if ($finalInstallEngine -and -not $skipAdvice) { Write-Host "[SUCCESS] rmspkg is now installed globally." -ForegroundColor Green }
    }
}

# APP INSTALL
$logFile = Join-Path $logRoot "$commandName.log"
Write-Log "Starting installation for $commandName"
$rollbackNeeded = $false
$createdDir = $false

try {
    if (-not $packageConfig) { throw "roms_package.json not found." }
    Check-RomsDependencies $packageConfig.dependencies

    if (-not (Test-Path $packageConfig.installDir)) {
        New-Item -ItemType Directory -Path $packageConfig.installDir -ErrorAction Stop | Out-Null
        $createdDir = $true; $rollbackNeeded = $true
        Write-Log "Created directory: $($packageConfig.installDir)"
    }

    if ($isRmsPackage) {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
        try {
            $pack = @($packageConfig.files) + @("roms_package.json")
            foreach ($f in $pack) {
                $e = $zip.Entries | Where-Object { $_.FullName -eq $f }
                if ($e) {
                    $d = Join-Path $packageConfig.installDir $f
                    $p = Split-Path $d
                    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $d, $true)
                    Write-Log "Extracted: $f"
                }
            }
        } finally { $zip.Dispose() }
    } else {
        foreach ($f in (@($packageConfig.files) + @("roms_package.json"))) {
            $s = Join-Path $PSScriptRoot $f; $d = Join-Path $packageConfig.installDir $f
            if ($s -ne $d) { Copy-Item $s $d -Force -ErrorAction Stop; Write-Log "Copied: $f" }
        }
    }

    $exec = $packageConfig.executable
    if (-not $exec) { $exec = Join-Path $packageConfig.installDir "$commandName.bat"
                      if (-not (Test-Path $exec)) { $exec = Join-Path $packageConfig.installDir "$commandName.ps1" } }
    Create-Shim $commandName $exec
    $final = $packageConfig
    if ($global:globalArtifacts.Count -gt 0) { $final | Add-Member -MemberType NoteProperty -Name "artifacts" -Value $global:globalArtifacts -Force }
    $final | ConvertTo-Json -Depth 10 | Out-File (Join-Path $metadataRoot "$commandName.json") -Encoding utf8
    Write-Log "Registered with $($global:globalArtifacts.Count) artifacts."

    $post = Join-Path $packageConfig.installDir "rms_install.ps1"
    if (Test-Path $post) { Write-Host "Running install hook..."; & $post 2>&1 | ForEach-Object { Write-Log "  [HOOK] $_" } }

    $rollbackNeeded = $false
    Write-Log "Installation completed successfully."
} catch {
    Write-Log "ERROR: $_" "ERROR"
    if ($rollbackNeeded) {
        if ($createdDir) { Remove-Item $packageConfig.installDir -Recurse -Force }
        $m = Join-Path $metadataRoot "$commandName.json"; if (Test-Path $m) { Remove-Item $m -Force }
    }
    Write-Error "[FATAL] Failed. See log: $logFile"; exit 1
}

Write-Host "-----------------------------------------------------"
Write-Host ""
Write-Host "[SUCCESS] $commandName installed."
Write-Host "          Log: $logFile"
Write-Host ""

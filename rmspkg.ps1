# rmspkg.ps1 - The ROMs-util Standalone Engine
# Usage: rmspkg <command> [inputPath] [flags]

# ---------------------------------------------
# ARGUMENT PARSING
# ---------------------------------------------
# Separates global flags (options) from positional data (command/path).
# Uses StartsWith("-") to identify flags, rest is command/input.
#
$flags = @($args | Where-Object { $_ -is [string] -and $_.StartsWith("-") })
[array]$data = @($args | Where-Object { -not ($_ -is [string] -and $_.StartsWith("-")) })

# Command-Based Actions: Plain words (Design Standard)
$command   = $data[0]
$inputPath = $data[1]

# Global Flag Pattern (Design Standard: $args -contains)
$global:AutoConfirm = ($flags -contains "-y") -or ($flags -contains "--yes")
$global:NoShim      = ($flags -contains "--no-shim")
$global:Roms_MirrorLogs = ($flags -contains "--mirror")

# Multi-Level Verbosity Parsing
$global:VerboseLevel = 0
if ($flags -contains "-vvv") { $global:VerboseLevel = 3 }
elseif ($flags -contains "-vv") { $global:VerboseLevel = 2 }
elseif ($flags -contains "-v" -or $flags -contains "--verbose") { $global:VerboseLevel = 1 }

# Legacy flag compatibility
$global:Verbose = ($global:VerboseLevel -gt 0)

# Bootstrap Detection (The Handshake)
$global:IsBootstrap = ($command -eq "bootstrap")

# ---------------------------------------------
# LOAD MODULES (Loading Sequence)
# ---------------------------------------------
$libPath = Join-Path $PSScriptRoot "lib"
if (-not (Test-Path $libPath)) {
    Write-Error "[FATAL] Library folder not found at $libPath"
    exit 1
}

# 1. Foundations
. (Join-Path $libPath "core.ps1")
. (Join-Path $libPath "help.ps1")
. (Join-Path $libPath "environment.ps1")
. (Join-Path $libPath "bootstrap.ps1")  # Self-Registration Logic

# 2. Logic
. (Join-Path $libPath "hooks.ps1")
. (Join-Path $libPath "installer.ps1")
. (Join-Path $libPath "uninstaller.ps1")

# ---------------------------------------------
# COMMAND ROUTING
# ---------------------------------------------
# Default to help if nothing provided or help requested
if (-not $global:IsBootstrap -and (-not $command -or $command -in @("help", "h", "?"))) {
    $invokedAs = if ($PSScriptRoot -notlike "*C:\roms*") { ".\rmspkg.bat" } else { "rmspkg" }
    Show-Help -invokedAs $invokedAs
    exit 0
}

# ---------------------------------------------
# IDENTITY DISCOVERY (The Brain)
# ---------------------------------------------
if ($args) { Write-Log "Raw Args: $($args -join ' ')" "RAW" }
if ($inputPath) { Write-Log "Input Path: $inputPath" "RAW" }
$packageConfig = $null
$isRmsPackage  = $false
$resolvedPath  = $null

# SPECIAL CASE: Bootstrap handles its own identity
if ($global:IsBootstrap) {
    $localJson = Join-Path $PSScriptRoot "roms_package.json"
    if (Test-Path $localJson) { $packageConfig = Get-Content $localJson -Raw | ConvertFrom-Json }
}
else {
    if ($inputPath) {
        # 1. Check if it's a direct file path
        if (Test-Path $inputPath -PathType Leaf) {
            $resolvedPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $inputPath))
            
            if ($resolvedPath.EndsWith(".rms", [System.StringComparison]::OrdinalIgnoreCase)) {
                $isRmsPackage = $true
                # Peek inside ZIP for manifest using native .NET
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                try {
                    $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedPath)
                    $entry = $zip.Entries | Where-Object { $_.FullName -eq "roms_package.json" }
                    if ($entry) {
                        $temp = Join-Path $env:TEMP "rmspkg_peek_$([guid]::NewGuid().ToString()).json"
                        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $temp)
                        $rawJson = Get-Content $temp -Raw
                        Write-Log "Raw Manifest Dump: $rawJson" "RAW"
                        $packageConfig = $rawJson | ConvertFrom-Json
                        Remove-Item $temp
                    }
                    $zip.Dispose()
                } catch { if ($zip) { $zip.Dispose() } }
            } elseif ($resolvedPath.EndsWith(".json", [System.StringComparison]::OrdinalIgnoreCase)) {
                $packageConfig = Get-Content $resolvedPath -Raw | ConvertFrom-Json
            }
        } 
        # 2. Check if it's a directory
        elseif (Test-Path $inputPath -PathType Container) {
            $resolvedPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $inputPath))
            $localJson = Join-Path $resolvedPath "roms_package.json"
            if (Test-Path $localJson) { $packageConfig = Get-Content $localJson -Raw | ConvertFrom-Json }
        }
        # 3. Assume it's an App Name (Registry Lookup)
        else {
            $metaJson = Join-Path $global:ROMs_METADATA "$inputPath.json"
            if (Test-Path $metaJson) {
                $packageConfig = Get-Content $metaJson -Raw | ConvertFrom-Json
            }
        }
    } elseif ($command -eq "uninstall") {
        # Naked uninstall, check current directory
        $localJson = Join-Path (Get-Location).Path "roms_package.json"
        if (Test-Path $localJson) { $packageConfig = Get-Content $localJson -Raw | ConvertFrom-Json }
    }
}

if (-not $packageConfig) {
    Write-Error "[FATAL] Could not identify package or application from input: '$inputPath'"
    exit 1
}

$commandName = $packageConfig.commandName

# ---------------------------------------------
# ADVICE (UX)
# ---------------------------------------------
$finalInstallEngine = $global:IsBootstrap
if (-not $global:AutoConfirm -and -not $global:IsQuiet -and -not (Test-Path $global:ROMs_ENGINE_DIR) -and -not (Test-Path $global:ROMs_ENGINE_BIN) -and ($PSScriptRoot -ne $global:ROMs_ENGINE_DIR)) {
    Write-Host "`nADVICE: rmspkg is running in portable mode." -ForegroundColor Yellow
    Write-Host "Would you like to install it permanently to $global:ROMs_ENGINE_DIR?"
    Write-Host "This will also register 'rmspkg' as a global command."
    $choice = Read-Host "Install rmspkg globally? (y/n)"
    if ($choice.Trim().ToLower() -eq "y") { $finalInstallEngine = $true }
}


# ---------------------------------------------
# EXECUTION
# ---------------------------------------------
# Initialize System Folders
@($global:ROMs_ROOT, $global:ROMs_METADATA, $global:ROMs_LOGS, $global:ROMs_BIN) | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null; if ($_ -eq $global:ROMs_METADATA) { (Get-Item $_).Attributes = "Hidden" } } }

# Environment Setup
Update-EnvironmentPath
Invoke-SelfBootstrap -finalInstallEngine $finalInstallEngine -scriptRoot $PSScriptRoot

# Action Routing
switch ($command) {
    "uninstall" {
        $script:logFile = Join-Path $global:ROMs_LOGS "$($packageConfig.name).log"
        Write-Log "Starting uninstallation for $commandName"
        Invoke-Uninstallation -packageConfig $packageConfig
        Write-Host "`n-----------------------------------------------------" -ForegroundColor Gray
        Write-Host "[SUCCESS] $commandName uninstalled." -ForegroundColor Green
        Write-Host "-----------------------------------------------------`n" -ForegroundColor Gray
        exit 0
    }
    "bootstrap" {
        # Bootstrap logic is handled in Invoke-SelfBootstrap above
        exit 0
    }
    "install" {
        $script:logFile = Join-Path $global:ROMs_LOGS "$($packageConfig.name).log"
        Write-Log "Starting installation for $commandName"
        try {
            $installedPath = Invoke-Installation -packageConfig $packageConfig -isRmsPackage $isRmsPackage -packagePath $resolvedPath -sourceDir (Split-Path $PSCommandPath) -noShim:$global:NoShim

            $packageId = if ($packageConfig.version) { "$($packageConfig.name)-$($packageConfig.version)" } else { $packageConfig.name }
            $foundExecutables = Find-PackageExecutables -AppDirectory $installedPath
            
            # Identify the primary executable
            $primaryExecutable = Join-Path $installedPath "$($packageConfig.commandName).bat"
            if (-not (Test-Path $primaryExecutable)) { $primaryExecutable = Join-Path $installedPath "$($packageConfig.commandName).exe" }
            if (-not (Test-Path $primaryExecutable)) { $primaryExecutable = Join-Path $installedPath "$($packageConfig.commandName).ps1" }
            if (-not (Test-Path $primaryExecutable) -and $foundExecutables.Count -gt 0) { $primaryExecutable = $foundExecutables[0] }

            $installationReport = [PSCustomObject]@{
                packageId = $packageId
                commandName = $packageConfig.commandName
                primaryExecutable = $primaryExecutable
                executables = $foundExecutables
            }
            $reportJson = $installationReport | ConvertTo-Json -Depth 10 -Compress
            Write-Log "Raw Installation Report: $reportJson" "RAW"
            $reportJson # Still output for pipeline compatibility
            
            # File Handshake
            $handshakeFile = Join-Path $global:ROMs_TEMP "handshake.json"
            $reportJson | Out-File -FilePath $handshakeFile -Encoding utf8 -Force

            Write-Host "`n-----------------------------------------------------" -ForegroundColor Gray
            Write-Host "[SUCCESS] $commandName installed." -ForegroundColor Green
            Write-Host "          Log: $script:logFile"
            Write-Host "-----------------------------------------------------`n" -ForegroundColor Gray
            exit 0
        } catch {
            Write-Error "[FATAL] Installation failed. See log: $script:logFile"
            exit 1
        }
    }
    Default {
        Write-Error "[FATAL] Unknown command: $command"
        exit 1
    }
}

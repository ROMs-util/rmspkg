[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Command,
    [Parameter(Position=1)]
    [string]$InputPath,
    
    # Global flags
    [Alias("y")][switch]$yes,

    # Internal parameters for orchestration
    [switch]$bootstrap,
    [switch]$quiet,
    [switch]$noShim
)

# ---------------------------------------------
# ARGUMENT PARSING (Modern Standard)
# ---------------------------------------------
$global:AutoConfirm = $yes -or ($args -contains "-y") -or ($args -contains "--yes")
$global:Verbose     = $PSBoundParameters.Verbose -or ($args -contains "-v") -or ($args -contains "--verbose")

# ---------------------------------------------
# LOAD MODULES
# ---------------------------------------------
$libPath = Join-Path $PSScriptRoot "lib"
if (-not (Test-Path $libPath)) {
    Write-Error "[FATAL] Library folder not found at $libPath"
    exit 1
}
. (Join-Path $libPath "core.ps1")
. (Join-Path $libPath "help.ps1")
. (Join-Path $libPath "environment.ps1")
. (Join-Path $libPath "hooks.ps1")
. (Join-Path $libPath "installer.ps1")
. (Join-Path $libPath "uninstaller.ps1")

# ---------------------------------------------
# COMMAND ROUTING
# ---------------------------------------------
# Default to help if nothing provided or help requested
if (-not $command -or $command -in @("help", "h", "?")) {
    $invokedAs = if ($PSScriptRoot -notlike "*C:\roms*") { ".\rmspkg.bat" } else { "rmspkg" }
    Show-Help -invokedAs $invokedAs
    exit 0
}

# ---------------------------------------------
# IDENTITY DISCOVERY (The Brain)
# ---------------------------------------------


# ---------------------------------------------
# IDENTITY DISCOVERY (The Brain)
# ---------------------------------------------
$packageConfig = $null
$isRmsPackage  = $false
$resolvedPath  = $null

if ($inputPath) {
    # 1. Check if it's a direct file path
    if (Test-Path $inputPath -PathType Leaf) {
        $resolvedPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $inputPath))
        
        if ($resolvedPath.EndsWith(".rms", [System.StringComparison]::OrdinalIgnoreCase)) {
            $isRmsPackage = $true
            # Peek inside ZIP for manifest
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            try {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedPath)
                $entry = $zip.Entries | Where-Object { $_.FullName -eq "roms_package.json" }
                if ($entry) {
                    $temp = Join-Path $env:TEMP "rmspkg_peek_$([guid]::NewGuid().ToString()).json"
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $temp)
                    $packageConfig = Get-Content $temp -Raw | ConvertFrom-Json
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
        $metaJson = Join-Path $metadataRoot "$inputPath.json"
        if (Test-Path $metaJson) {
            $packageConfig = Get-Content $metaJson -Raw | ConvertFrom-Json
        }
    }
} elseif ($command -eq "uninstall") {
    # Naked uninstall, check current directory
    $localJson = Join-Path (Get-Location).Path "roms_package.json"
    if (Test-Path $localJson) { $packageConfig = Get-Content $localJson -Raw | ConvertFrom-Json }
}

if (-not $packageConfig) {
    Write-Error "[FATAL] Could not identify package or application from input: '$inputPath'"
    exit 1
}

$commandName = $packageConfig.commandName

# ---------------------------------------------
# ADVICE & ELEVATION (DEPRECATED: Manager handles elevation)
# ---------------------------------------------
$finalInstallEngine = $bootstrap
if (-not $quiet -and -not (Test-Path $engineDir) -and -not (Test-Path $engineShim) -and ($PSScriptRoot -ne $engineDir)) {
    Write-Host "`nADVICE: rmspkg is running in portable mode." -ForegroundColor Yellow
    Write-Host "Would you like to install it permanently to $engineDir?"
    Write-Host "This will also register 'rmspkg' as a global command."
    $choice = Read-Host "Install rmspkg globally? (y/n)"
    if ($choice.Trim().ToLower() -eq "y") { $finalInstallEngine = $true }
}

# ---------------------------------------------
# EXECUTION
# ---------------------------------------------

# Initialize System
@($systemRoot, $metadataRoot, $logRoot, $binRoot) | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null; if ($_ -eq $metadataRoot) { (Get-Item $_).Attributes = "Hidden" } } }

# Environment Setup
Update-EnvironmentPath
Invoke-SelfBootstrap -finalInstallEngine $finalInstallEngine -scriptRoot $PSScriptRoot -engineDir $engineDir -engineShimPath $engineShim

# Action Routing
switch ($command) {
    "uninstall" {
        Invoke-Uninstallation -packageConfig $packageConfig
        Write-Host "`n-----------------------------------------------------"
        Write-Host "[SUCCESS] $commandName uninstalled."
        Write-Host "-----------------------------------------------------`n"
    }
    "install" {
        $logFile = Join-Path $logRoot "$($packageConfig.name).log"
        Write-Log "Starting installation for $commandName"
        try {
            $installedPath = Invoke-Installation -packageConfig $packageConfig -isRmsPackage $isRmsPackage -packagePath $resolvedPath -sourceDir (Split-Path $PSCommandPath) -noShim:$noShim

            $packageId = if ($packageConfig.version) { "$($packageConfig.name)-$($packageConfig.version)" } else { $packageConfig.name }
            $foundExecutables = Find-PackageExecutables -AppDirectory $installedPath
            
            # Identify the primary executable (the one the user actually calls)
            $primaryExecutable = Join-Path $installedPath "$($packageConfig.commandName).bat"
            if (-not (Test-Path $primaryExecutable)) { $primaryExecutable = Join-Path $installedPath "$($packageConfig.commandName).exe" }
            if (-not (Test-Path $primaryExecutable)) { $primaryExecutable = Join-Path $installedPath "$($packageConfig.commandName).ps1" }
            # Fallback to the first found executable if the named one doesn't exist
            if (-not (Test-Path $primaryExecutable) -and $foundExecutables.Count -gt 0) { $primaryExecutable = $foundExecutables[0] }

            $installationReport = [PSCustomObject]@{
                packageId = $packageId
                commandName = $packageConfig.commandName
                primaryExecutable = $primaryExecutable
                executables = $foundExecutables
            }
            $installationReport | ConvertTo-Json -Depth 10 -Compress

            Write-Host "`n-----------------------------------------------------"
            Write-Host "[SUCCESS] $commandName installed."
            Write-Host "          Log: $logFile"
            Write-Host "-----------------------------------------------------`n"
        } catch {
            Write-Error "[FATAL] Installation failed. See log: $logFile"
            exit 1
        }
    }
    Default {
        Write-Error "[FATAL] Unknown command: $command"
        exit 1
    }
}

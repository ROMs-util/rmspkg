<#
.SYNOPSIS
    Generic script installer - reads roms_package.json and installs to system.

.DESCRIPTION
    - Reads config from roms_package.json in the same directory
    - Validates system and tool dependencies
    - Creates install directory if not exists
    - Copies all listed files to install directory
    - Adds install directory to User PATH

.EXAMPLE
    .\install.ps1
#>

param(
    [Parameter(Mandatory = $false)]
    [switch]$uninstall
)

$scriptDir  = Split-Path -Parent $PSCommandPath
$configFile = Join-Path $scriptDir "roms_package.json"

# ---------------------------------------------
# ELEVATION CHECK
# ---------------------------------------------
$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($uninstall) { $argList += "-uninstall" }
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit 0
}

# ---------------------------------------------
# READ CONFIG FILE
# ---------------------------------------------
if (-not (Test-Path $configFile)) {
    Write-Error "[ERROR] roms_package.json not found in $scriptDir"
    exit 1
}

try {
    $config = Get-Content $configFile -Raw | ConvertFrom-Json
} catch {
    Write-Error "[ERROR] Failed to parse roms_package.json: $_"
    exit 1
}

# ---------------------------------------------
# VALIDATE REQUIRED CONFIG FIELDS
# ---------------------------------------------
if (-not $config.installDir) {
    Write-Error "[ERROR] roms_package.json missing required field: installDir"
    exit 1
}
if (-not $config.commandName) {
    Write-Error "[ERROR] roms_package.json missing required field: commandName"
    exit 1
}
if (-not $config.files -or $config.files.Count -eq 0) {
    Write-Error "[ERROR] roms_package.json missing required field: files"
    exit 1
}

$installDir  = $config.installDir
$commandName = $config.commandName
$files       = $config.files

# ---------------------------------------------
# UNINSTALL MODE
# ---------------------------------------------
if ($uninstall) {
    Write-Host ""
    Write-Host "Uninstaller - $commandName"
    Write-Host "-----------------------------------------------------"

    $confirm = Read-Host "This will delete $installDir and remove it from PATH. Proceed? (y/n)"
    if ($confirm.Trim().ToLower() -ne "y") {
        Write-Host "[ABORTED] No changes made."
        exit 0
    }

    if (Test-Path $installDir) {
        try {
            Remove-Item -Path $installDir -Recurse -Force -ErrorAction Stop
            Write-Host "[REMOVED]   $installDir"
        } catch {
            Write-Host "[FAILED]    Could not remove $installDir -> $_"
            exit 1
        }
    } else {
        Write-Host "[NOT FOUND] $installDir does not exist"
    }

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (($currentPath -split ";") -contains $installDir) {
        try {
            $newPath = ($currentPath -split ";" | Where-Object { $_ -ne $installDir }) -join ";"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            Write-Host "[PATH]      $installDir removed from User PATH"
        } catch {
            Write-Host "[FAILED]    Could not update User PATH -> $_"
            exit 1
        }
    } else {
        Write-Host "[NOT FOUND] $installDir not in User PATH"
    }

    Write-Host "-----------------------------------------------------"
    Write-Host ""
    Write-Host "[SUCCESS] $commandName uninstalled."
    Write-Host "          Open a new terminal to apply PATH changes."
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "Installer - $commandName"
Write-Host "-----------------------------------------------------"

# ---------------------------------------------
# CHECK SYSTEM DEPENDENCIES
# ---------------------------------------------
if ($config.dependencies -and $config.dependencies.system) {
    $sys = $config.dependencies.system

    if ($sys.powershell) {
        $currentPS  = $PSVersionTable.PSVersion.Major
        $requiredPS = [int]($sys.powershell.Split(".")[0])
        if ($currentPS -lt $requiredPS) {
            Write-Error "[ERROR] PowerShell $($sys.powershell) or higher required. Current: $currentPS"
            exit 1
        }
        Write-Host "[OK]        PowerShell $currentPS meets requirement ($($sys.powershell) required)"
    }

    if ($sys.os) {
        Write-Host "[INFO]      Required OS: $($sys.os)"
    }
}

# ---------------------------------------------
# CHECK TOOL DEPENDENCIES
# ---------------------------------------------
if ($config.dependencies -and $config.dependencies.tools) {
    $tools = $config.dependencies.tools

    foreach ($tool in $tools.PSObject.Properties) {
        $toolName = $tool.Name
        $toolType = $tool.Value.Trim().ToLower()
        $found    = $null -ne (Get-Command $toolName -ErrorAction SilentlyContinue)

        if ($found) {
            Write-Host "[OK]        $toolName found"
        } elseif ($toolType -eq "required") {
            Write-Error "[ERROR] Required tool '$toolName' not found. Please install it and retry."
            exit 1
        } else {
            Write-Host "[WARNING]   Optional tool '$toolName' not found - some features may not work"
        }
    }
}

# ---------------------------------------------
# CREATE INSTALL DIRECTORY
# ---------------------------------------------
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
    Write-Host "[CREATED]   $installDir"
} else {
    Write-Host "[EXISTS]    $installDir"
}

# ---------------------------------------------
# COPY FILES
# ---------------------------------------------
$copyFailed = $false

# Always include roms_package.json — needed for uninstall, update, repair
$allFiles = @($files) + @("roms_package.json")

foreach ($file in $allFiles) {
    $src  = Join-Path $scriptDir $file
    $dest = Join-Path $installDir $file

    if (-not (Test-Path $src)) {
        Write-Host "[MISSING]   $file not found in $scriptDir"
        $copyFailed = $true
        continue
    }

    try {
        Copy-Item -Path $src -Destination $dest -Force -ErrorAction Stop
        Write-Host "[COPIED]    $file -> $installDir"
    } catch {
        Write-Host "[FAILED]    Could not copy $file -> $_"
        $copyFailed = $true
    }
}

if ($copyFailed) {
    Write-Host ""
    Write-Host "[ERROR] Installation incomplete. Check missing files above."
    exit 1
}

# ---------------------------------------------
# ADD TO USER PATH
# ---------------------------------------------
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")

if (($currentPath -split ";") -contains $installDir) {
    Write-Host "[EXISTS]    $installDir already in User PATH"
} else {
    try {
        [Environment]::SetEnvironmentVariable("PATH", $currentPath + ";" + $installDir, "User")
        Write-Host "[PATH]      $installDir added to User PATH"
    } catch {
        Write-Host "[FAILED]    Could not update User PATH -> $_"
        exit 1
    }
}

# ---------------------------------------------
# DONE
# ---------------------------------------------
Write-Host "-----------------------------------------------------"
Write-Host ""
Write-Host "[SUCCESS] $commandName installed."
Write-Host "          Open a new terminal and type: $commandName"
Write-Host ""
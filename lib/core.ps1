# ---------------------------------------------
# GLOBALS & PATHS
# ---------------------------------------------
$systemRoot   = "C:\roms"
$metadataRoot = Join-Path $systemRoot ".metadata"
$logRoot      = Join-Path $systemRoot "logs"
$binRoot      = Join-Path $systemRoot "bin"
$engineDir    = Join-Path $systemRoot "rmspkg"
$engineShim   = Join-Path $binRoot "rmspkg.bat"

# Global state
$script:logFile = $null
$global:globalArtifacts = @()

# ---------------------------------------------
# LOGGING SYSTEM
# ---------------------------------------------
function Write-Log {
    param([string]$message, [string]$level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$level] $message"
    Write-Host $logEntry
    if ($script:logFile) {
        $logEntry | Out-File -FilePath $script:logFile -Append -Encoding utf8
    }
}

# ---------------------------------------------
# DEPENDENCY VALIDATION
# ---------------------------------------------
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
# ELEVATION UTILITY
# ---------------------------------------------
function Confirm-Elevation {
    param([string]$cmdPath, [hashtable]$params)
    
    $currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[INFO] Elevation required to modify $systemRoot. Requesting Administrator privileges..."
        
        $argString = "-NoExit -ExecutionPolicy Bypass -File `"$cmdPath`""
        if ($params.command) { $argString += " $($params.command)" }
        if ($params.inputPath) { $argString += " `"$($params.inputPath)`"" }
        if ($params.installEngine) { $argString += " -installEngine" }
        $argString += " -skipAdvice" 
        
        Start-Process powershell -Verb RunAs -ArgumentList $argString
        return $false
    }
    return $true
}

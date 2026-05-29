# ---------------------------------------------
# GLOBALS & PATHS (Ecosystem Standard)
# ---------------------------------------------
$global:ROMS_ROOT     = "C:\roms"
$global:METADATA_DIR  = "$global:ROMS_ROOT\.metadata"
$global:LOG_DIR       = "$global:ROMS_ROOT\logs"
$global:BIN_DIR       = "$global:ROMS_ROOT\bin"
$global:MASTER_LOG    = "$global:LOG_DIR\roms.log"

$global:ENGINE_DIR    = Join-Path $global:ROMS_ROOT "rmspkg"
$global:ENGINE_BIN    = Join-Path $global:BIN_DIR "rmspkg.bat"

# Global state
$script:logFile = $null
$global:globalArtifacts = @()

# ---------------------------------------------
# LOGGING SYSTEM
# ---------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG", "TRACE", "RAW")][string]$Level = "INFO",
        [string]$Source = "Engine"
    )

    # Initialize global verbosity if not set
    if ($null -eq $global:VerboseLevel) { $global:VerboseLevel = 0 }

    if (-not (Test-Path $global:LOG_DIR)) {
        New-Item -ItemType Directory -Path $global:LOG_DIR -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # 1. INDUSTRIAL DATA PREPARATION (Extract JSON once)
    $isJson = ($Message -match "^\s*\{" -or $Message -match "^\s*\[" -or $Message -match ":\s*\{" -or $Message -match ":\s*\[")
    $prefix = ""
    $jsonObj = $null
    
    if ($isJson) {
        try {
            # Extraction logic (Non-greedy prefix capture)
            if ($Message -match "(?s)(.*?):\s*([\{\[].*)") {
                $prefix = $matches[1].Trim()
                $jsonObj = $matches[2].Trim() | ConvertFrom-Json
            } else {
                $jsonObj = $Message | ConvertFrom-Json
            }
        } catch { 
            $isJson = $false # False positive or corrupt JSON
        }
    }

    # 2. FILE LOGGING (Tight Inline: One Line, One Event)
    $fileContent = if ($isJson) {
        $compactJson = $jsonObj | ConvertTo-Json -Depth 10 -Compress
        if ($prefix) { "${prefix}: $compactJson" } else { $compactJson }
    } else {
        # Flatten multi-line strings for log consistency
        ($Message -split "\r?\n" | ForEach-Object { $_.Trim() }) -join " "
    }

    # Log to BOTH the master log and the task-specific log if available
    $logFileLine = "[$timestamp] [$Level] [$Source] $fileContent"
    $targetLogs = @($global:MASTER_LOG)
    if ($script:logFile) { $targetLogs += $script:logFile }

    foreach ($logPath in $targetLogs) {
        $retryCount = 0
        $success = $false
        while (-not $success -and $retryCount -lt 5) {
            try {
                $logFileLine | Out-File -FilePath $logPath -Append -Encoding utf8 -ErrorAction Stop
                $success = $true
            } catch {
                $retryCount++
                Start-Sleep -Milliseconds 50
            }
        }
    }

    # 3. CONSOLE OUTPUT (Pretty-RAW for Humans)
    $shouldDisplay = $true
    if ($Level -eq "DEBUG" -and $global:VerboseLevel -lt 1) { $shouldDisplay = $false }
    elseif ($Level -eq "TRACE" -and $global:VerboseLevel -lt 2) { $shouldDisplay = $false }
    elseif ($Level -eq "RAW"   -and $global:VerboseLevel -lt 3) { $shouldDisplay = $false }

    if ($shouldDisplay) {
        $consoleContent = if ($isJson -and $Level -eq "RAW") {
            $prettyJson = $jsonObj | ConvertTo-Json -Depth 10
            if ($prefix) { "${prefix}:`n$prettyJson" } else { $prettyJson }
        } else {
            $Message
        }

        $consoleLine = if ($global:VerboseLevel -ge 1) { "[$timestamp] [$Level] [$Source] $consoleContent" } else { "[$Level] [$Source] $consoleContent" }
        
        $color = switch ($Level) {
            "ERROR"   { "Red" }
            "WARN"    { "Yellow" }
            "SUCCESS" { "Green" }
            "DEBUG"   { "Gray" }
            "TRACE"   { "Cyan" }
            "RAW"     { "Magenta" }
            Default   { "Gray" }
        }
        Write-Host $consoleLine -ForegroundColor $color
    }
}

# ---------------------------------------------
# DEPENDENCY VALIDATION
# ---------------------------------------------
function Check-RomsDependencies {
    param($dependencies)
    if ($null -eq $dependencies) { return }
    
    $depNames = @()
    if ($dependencies -is [System.Array]) {
        $depNames = $dependencies
    } elseif ($dependencies.roms -is [System.Array]) {
        $depNames = $dependencies.roms
    }

    foreach ($depName in $depNames) {
        # Strip version constraint for registry check (Manager handles resolution)
        $cleanName = $depName.Split(':')[0]
        if (-not (Test-Path (Join-Path $global:METADATA_DIR "$cleanName.json"))) {
            throw "Missing required package dependency: '$depName'. Please install it first."
        }
        Write-Log "Verified dependency: $depName" "DEBUG"
    }
}

# ---------------------------------------------
# ELEVATION UTILITY
# ---------------------------------------------
function Confirm-Elevation {
    param([string]$cmdPath, [hashtable]$params)
    
    $currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Elevation required to modify $global:ROMS_ROOT. Requesting Administrator privileges..." "INFO"
        
        $argString = "-NoExit -ExecutionPolicy Bypass -File `"$cmdPath`""
        if ($params.command) { $argString += " $($params.command)" }
        if ($params.inputPath) { $argString += " `"$($params.inputPath)`"" }
        if ($params.installEngine) { $argString += " -installEngine" }
        
        # Explicitly forward verbosity flags to the elevated process
        if ($global:VerboseLevel -eq 3) { $argString += " -vvv" }
        elseif ($global:VerboseLevel -eq 2) { $argString += " -vv" }
        elseif ($global:VerboseLevel -eq 1) { $argString += " -v" }

        $argString += " -skipAdvice" 
        
        Start-Process powershell -Verb RunAs -ArgumentList $argString
        return $false
    }
    return $true
}

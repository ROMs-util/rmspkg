# ---------------------------------------------
# GLOBALS & PATHS (Ecosystem Standard)
# ---------------------------------------------
$global:ROMs_ROOT         = "C:\roms"
$global:ROMs_METADATA     = "$global:ROMs_ROOT\.metadata"
$global:ROMs_LOGS         = "$global:ROMs_ROOT\logs"
$global:ROMs_BIN          = "$global:ROMs_ROOT\bin"
$global:ROMs_MASTER_LOG   = "$global:ROMs_LOGS\roms.log"

$global:ROMs_ENGINE_DIR   = Join-Path $global:ROMs_ROOT "rmspkg"
$global:ROMs_ENGINE_BIN   = Join-Path $global:ROMs_BIN "rmspkg.bat"

$global:ROMs_TEMP         = "$global:ROMs_ROOT\temp"

# Global state
$script:logFile = $null
$global:globalArtifacts = @()

# ---------------------------------------------
# LOGGING SYSTEM
# Writes timestamped log entries to console (colored by level) and master log file.
# HOW IT WORKS:
# 1. Detect JSON in message and pretty-print for readability.
# 2. Format output with timestamp, source, and level badge.
# 3. Write to $global:ROMs_MASTER_LOG with retry logic for locked files.
# 4. Output to console with color coding (INFO=White, WARN=Yellow, ERROR=Red, etc.).
# Uses global $VerboseLevel: 0=INFO/WARN/ERROR/SUCCESS, 1=+DEBUG, 2=+TRACE, 3=+RAW
# ---------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG", "TRACE", "RAW")][string]$Level = "INFO",
        [string]$Source = "Engine"
    )

    # Initialize global verbosity if not set
    if ($null -eq $global:VerboseLevel) { $global:VerboseLevel = 0 }

    if (-not (Test-Path $global:ROMs_LOGS)) {
        New-Item -ItemType Directory -Path $global:ROMs_LOGS -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # 1. DATA PREPARATION (Extract JSON once)
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
    $targetLogs = @($global:ROMs_MASTER_LOG)
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
# ---------------------------------------------
# DEPENDENCY VERIFICATION
# Checks if package runtime dependencies are installed in the system.
# HOW IT WORKS:
# 1. Load all metadata files from $global:ROMs_METADATA.
# 2. For each dependency, check if its metadata file exists.
# 3. Show ERROR and return $false if any dependency is missing.
# 4. Return $true if all dependencies satisfied.
# Used before package installation to prevent partial installs.
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
        if (-not (Test-Path (Join-Path $global:ROMs_METADATA "$cleanName.json"))) {
            throw "Missing required package dependency: '$depName'. Please install it first."
        }
        Write-Log "Verified dependency: $depName" "DEBUG"
    }
}

# ---------------------------------------------
# ELEVATION UTILITY
# ---------------------------------------------
# ---------------------------------------------
# ADMINISTRATOR ELEVATION CHECK
# Verifies the current process is running with Administrator privileges.
# HOW IT WORKS:
# 1. Create WindowsPrincipal from current identity.
# 2. Check if identity is in Administrators role.
# 3. Return $true if elevated, $false otherwise.
# ---------------------------------------------
function Confirm-Elevation {
    param([string]$cmdPath, [hashtable]$params)
    
    $currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Elevation required to modify $global:ROMs_ROOT. Requesting Administrator privileges..." "INFO"
        
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

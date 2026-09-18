# environment.ps1 - System PATH and Shim management logic

# ---------------------------------------------
# SHIM CREATION
# Creates a CMD wrapper script that redirects to the actual executable.
# HOW IT WORKS:
# 1. Create .bat file in $global:ROMs_BIN with the command name.
# 2. If execPath ends in .ps1, use powershell -File; otherwise use call.
# 3. Track created shim in $global:globalArtifacts for cleanup.
# ---------------------------------------------
function Get-CmdEscapedPath {
    # Escapes a path so it is safe to embed inside a quoted CMD (batch) command line.
    # CMD treats & | < > ^ as metacharacters and %N as variables; escaping each with
    # a caret preserves the literal path when the generated shim is executed.
    param([string]$Path)
    $Path = $Path.Replace("^", "^^")
    foreach ($ch in @("&", "|", "<", ">")) {
        $Path = $Path.Replace($ch, "^$ch")
    }
    return $Path
}

function Create-Shim {
    param([string]$name, [string]$execPath)
    $shimPath = Join-Path $global:ROMs_BIN "$name.bat"
    $safePath = Get-CmdEscapedPath $execPath
    $content = if ($execPath.EndsWith(".ps1")) { "@echo off`npowershell -ExecutionPolicy Bypass -File `"$safePath`" %*" }
               else { "@echo off`ncall `"$safePath`" %*" }
    $content | Out-File -FilePath $shimPath -Encoding ascii
    Write-Log "Created shim: $name -> $execPath" "INFO"
    if ($global:globalArtifacts -notcontains $shimPath) { $global:globalArtifacts += $shimPath }
}

# ---------------------------------------------
# ENVIRONMENT VARIABLE ORCHESTRATION (Set)
# Applies the manifest 'environment_variables' object as persistent system
# settings and registers each one as an 'env:' artifact so uninstall can purge it.
# HOW IT WORKS:
# 1. Iterate the PSCustomObject properties from the manifest.
# 2. Attempt a Machine-scope write; if the registry denies it (process is not
#    elevated), fall back to the User scope and log a WARN instead of failing
#    the whole installation.
# 3. Append "env:<KEY>" to $global:globalArtifacts. The marker is scope-neutral
#    on purpose: removal clears both scopes so a variable can never survive its
#    package, regardless of which scope the write landed in.
# ---------------------------------------------
function Invoke-RomsEnvironmentSet {
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Variables,
        [string]$Scope = "Machine"
    )

    foreach ($prop in $Variables.PSObject.Properties) {
        $envKey = $prop.Name
        $envVal = $prop.Value
        $targetScope = $Scope

        if ($targetScope -eq "Machine") {
            $preVal = [Environment]::GetEnvironmentVariable($envKey, "Machine")
            try {
                if ($null -ne $preVal -and $preVal -ne $envVal) {
                    Write-Log "Machine variable '$envKey' currently differs from the manifest (current: '$preVal'). The Machine write will replace it if elevation succeeds. Previous value is not backed up and will be lost on uninstall." "WARN"
                }
                [System.Environment]::SetEnvironmentVariable($envKey, $envVal, "Machine")
            } catch {
                Write-Log "Machine scope denied (not elevated). Writing $envKey to User scope instead." "WARN"
                $targetScope = "User"
            }
        }
        if ($targetScope -eq "User") {
            $preVal = [Environment]::GetEnvironmentVariable($envKey, "User")
            if ($null -ne $preVal -and $preVal -ne $envVal) {
                Write-Log "Overwriting existing User variable '$envKey' (current: '$preVal'). Previous value is not backed up and will be lost on uninstall." "WARN"
            }
            [System.Environment]::SetEnvironmentVariable($envKey, $envVal, "User")
        }
        Write-Log "Setting Environment Variable: $envKey = $envVal ($targetScope)" "INFO"

        # Track as environment artifact for clean uninstallation
        $artifactKey = "env:$envKey"
        if ($global:globalArtifacts -notcontains $artifactKey) {
            $global:globalArtifacts += $artifactKey
        }
    }
}

# ---------------------------------------------
# ENVIRONMENT VARIABLE ORCHESTRATION (Remove)
# Purges a tracked environment variable from persistent storage during uninstall.
# HOW IT WORKS:
# 1. Clear the Machine scope guarded by try/catch: a non-elevated uninstall must
#    not crash, so a denied registry write is reported as WARN and skipped.
# 2. Clear the User scope unconditionally (always writable by the current user).
# Writing both scopes mirrors the Set fallback and guarantees no orphan variable
# survives the package that created it.
# NOTE: the deletion value is [NullString]::Value, NOT a bare $null. PowerShell
# binds $null to the String parameter as "" and .NET then *writes an empty
# REG_SZ* instead of deleting the value, leaving a ghost variable behind.
# [NullString]::Value passes a real CLR null, which makes SetEnvironmentVariable
# remove the registry value outright (verified empirically on PS 7.6.6).
# ---------------------------------------------
function Invoke-RomsEnvironmentRemove {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [string]$Scope = "Machine"
    )

    if ($Scope -eq "Machine") {
        try {
            [System.Environment]::SetEnvironmentVariable($Key, [NullString]::Value, "Machine")
            Write-Log "Removed Environment Variable: $Key (Machine)" "INFO"
        } catch {
            Write-Log "Could not remove $Key from Machine scope (elevation required)." "WARN"
        }
    }
    [System.Environment]::SetEnvironmentVariable($Key, [NullString]::Value, "User")
    Write-Log "Removed Environment Variable: $Key (User)" "INFO"
}

# ---------------------------------------------
# PATH ENVIRONMENT UPDATE
# Adds $global:ROMs_BIN to the User PATH environment variable if not present.
# HOW IT WORKS:
# 1. Get current User PATH.
# 2. Check if $global:ROMs_BIN is already in the list.
# 3. If not, append it and save via SetEnvironmentVariable.
# Shows warning that terminal restart may be needed.
# ---------------------------------------------
function Update-EnvironmentPath {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not (($currentPath -split ";") -contains $global:ROMs_BIN)) {
        Write-Log "Adding $global:ROMs_BIN to User PATH..." "INFO"
        [Environment]::SetEnvironmentVariable("PATH", $currentPath + ";" + $global:ROMs_BIN, "User")
        Write-Host "[PATH] Added $global:ROMs_BIN to User PATH. Restart terminal to apply." -ForegroundColor Yellow
    }
}

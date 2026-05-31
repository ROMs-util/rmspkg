# environment.ps1 - System PATH and Shim management logic

# ---------------------------------------------
# SHIM CREATION
# Creates a CMD wrapper script that redirects to the actual executable.
# HOW IT WORKS:
# 1. Create .bat file in $global:ROMs_BIN with the command name.
# 2. If execPath ends in .ps1, use powershell -File; otherwise use call.
# 3. Track created shim in $global:globalArtifacts for cleanup.
# ---------------------------------------------
function Create-Shim {
    param([string]$name, [string]$execPath)
    $shimPath = Join-Path $global:ROMs_BIN "$name.bat"
    $content = if ($execPath.EndsWith(".ps1")) { "@echo off`npowershell -ExecutionPolicy Bypass -File `"$execPath`" %*" }
               else { "@echo off`ncall `"$execPath`" %*" }
    $content | Out-File -FilePath $shimPath -Encoding ascii
    Write-Log "Created shim: $name -> $execPath" "INFO"
    if ($global:globalArtifacts -notcontains $shimPath) { $global:globalArtifacts += $shimPath }
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

# environment.ps1 - System PATH and Shim management logic

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

function Invoke-RomsEnvironmentSet {
    param(
        [Parameter(Mandatory=$true)][PSCustomObject]$Variables,
        [string]$Scope = "Machine"
    )

    foreach ($prop in $Variables.PSObject.Properties) {
        $key = $prop.Name
        $val = $prop.Value
        Write-Log "Setting Environment Variable: $key = $val ($Scope)" "INFO"
        [System.Environment]::SetEnvironmentVariable($key, $val, $Scope)
        
        # Track as environment artifact for clean uninstallation
        $artifactKey = "env:$key"
        if ($global:globalArtifacts -notcontains $artifactKey) { 
            $global:globalArtifacts += $artifactKey 
        }
    }
}

function Invoke-RomsEnvironmentRemove {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [string]$Scope = "Machine"
    )

    Write-Log "Removing Environment Variable: $Key ($Scope)" "INFO"
    [System.Environment]::SetEnvironmentVariable($Key, $null, $Scope)
}


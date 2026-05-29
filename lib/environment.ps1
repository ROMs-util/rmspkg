# environment.ps1 - System PATH and Shim management logic

function Create-Shim {
    param([string]$name, [string]$execPath)
    $shimPath = Join-Path $global:BIN_DIR "$name.bat"
    $content = if ($execPath.EndsWith(".ps1")) { "@echo off`npowershell -ExecutionPolicy Bypass -File `"$execPath`" %*" }
               else { "@echo off`ncall `"$execPath`" %*" }
    $content | Out-File -FilePath $shimPath -Encoding ascii
    Write-Log "Created shim: $name -> $execPath" "INFO"
    if ($global:globalArtifacts -notcontains $shimPath) { $global:globalArtifacts += $shimPath }
}

function Update-EnvironmentPath {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not (($currentPath -split ";") -contains $global:BIN_DIR)) {
        Write-Log "Adding $global:BIN_DIR to User PATH..." "INFO"
        [Environment]::SetEnvironmentVariable("PATH", $currentPath + ";" + $global:BIN_DIR, "User")
        Write-Host "[PATH] Added $global:BIN_DIR to User PATH. Restart terminal to apply." -ForegroundColor Yellow
    }
}

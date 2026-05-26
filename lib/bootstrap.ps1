# bootstrap.ps1 - Standalone Engine Self-Registration logic

# ---------------------------------------------
# SELF-HEALING BOOTSTRAP (Handshake Logic)
# ---------------------------------------------
function Invoke-SelfBootstrap {
    param([bool]$finalInstallEngine, [string]$scriptRoot, [string]$engineDir, [string]$engineShimPath)
    
    if ($finalInstallEngine -or ($scriptRoot -eq $engineDir)) {
        if (-not (Test-Path $engineDir)) { New-Item -ItemType Directory -Path $engineDir -Force | Out-Null }
        
        if ($scriptRoot -ne $engineDir) {
            Write-Log "Installing rmspkg engine to system root..."
            # Copy main script and entire lib folder
            Copy-Item (Join-Path $scriptRoot "rmspkg.ps1") (Join-Path $engineDir "rmspkg.ps1") -Force
            Copy-Item (Join-Path $scriptRoot "lib") $engineDir -Recurse -Force
            
            $engineManifest = Join-Path $scriptRoot "roms_package.json"
            if (Test-Path $engineManifest) { Copy-Item $engineManifest (Join-Path $engineDir "roms_package.json") -Force }
        }

        if ($finalInstallEngine -or -not (Test-Path $engineShimPath)) {
            if (-not (Test-Path $engineShimPath)) { Create-Shim "rmspkg" (Join-Path $engineDir "rmspkg.ps1") }
            
            $localManifest = Join-Path $engineDir "roms_package.json"
            if (Test-Path $localManifest) {
                $eConfig = Get-Content $localManifest -Raw | ConvertFrom-Json
                $eConfig | Add-Member -MemberType NoteProperty -Name "artifacts" -Value @($engineShimPath) -Force
                $eConfig | ConvertTo-Json -Depth 10 | Out-File (Join-Path $metadataRoot "rmspkg.json") -Encoding utf8
                Write-Log "Engine registered in metadata database"
            }
            $global:globalArtifacts = @() # Reset for app
        }
    }
}

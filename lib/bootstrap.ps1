# bootstrap.ps1 - Standalone Engine Self-Registration logic

# ---------------------------------------------
# SELF-HEALING BOOTSTRAP (Handshake Logic)
# ---------------------------------------------
function Invoke-SelfBootstrap {
    param([bool]$finalInstallEngine, [string]$scriptRoot)
    
    if ($finalInstallEngine -or ($scriptRoot -eq $global:ENGINE_DIR)) {
        if (-not (Test-Path $global:ENGINE_DIR)) { New-Item -ItemType Directory -Path $global:ENGINE_DIR -Force | Out-Null }
        
        if ($scriptRoot -ne $global:ENGINE_DIR) {
            Write-Log "Installing rmspkg engine to system root..." "INFO"
            # Copy main script and entire lib folder
            Write-Log "Tracing bootstrap copy: rmspkg.ps1" "TRACE"
            Copy-Item (Join-Path $scriptRoot "rmspkg.ps1") (Join-Path $global:ENGINE_DIR "rmspkg.ps1") -Force
            
            # Iterative library copy for Total Visibility
            $libSrc = Join-Path $scriptRoot "lib"
            if (Test-Path $libSrc) {
                Get-ChildItem -Path $libSrc -File | ForEach-Object {
                    $src = $_.FullName
                    $dest = Join-Path $global:ENGINE_DIR "lib/$($_.Name)"
                    $destParent = Split-Path $dest
                    if (-not (Test-Path $destParent)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
                    
                    Write-Log "Tracing bootstrap library copy: lib/$($_.Name)" "TRACE"
                    Copy-Item $src $dest -Force
                }
            }
            
            $engineManifest = Join-Path $scriptRoot "roms_package.json"
            if (Test-Path $engineManifest) { 
                Write-Log "Tracing bootstrap manifest copy: roms_package.json" "TRACE"
                Copy-Item $engineManifest (Join-Path $global:ENGINE_DIR "roms_package.json") -Force 
            }
        }

        if ($finalInstallEngine -or -not (Test-Path $global:ENGINE_BIN)) {
            if (-not (Test-Path $global:ENGINE_BIN)) { 
                Write-Log "Tracing shim creation: rmspkg" "TRACE"
                Create-Shim "rmspkg" (Join-Path $global:ENGINE_DIR "rmspkg.ps1") 
            }
            
            $localManifest = Join-Path $global:ENGINE_DIR "roms_package.json"
            if (Test-Path $localManifest) {
                $eConfig = Get-Content $localManifest -Raw | ConvertFrom-Json
                Write-Log "Raw Engine Config before registration: $($eConfig | ConvertTo-Json -Compress)" "RAW"
                $eConfig | Add-Member -MemberType NoteProperty -Name "artifacts" -Value @($global:ENGINE_BIN) -Force
                $eConfig | ConvertTo-Json -Depth 10 | Out-File (Join-Path $global:METADATA_DIR "rmspkg.json") -Encoding utf8
                
                # TRUTH SIGNATURE (For Verification)
                Write-Log "Modular Engine Handshake active." "SUCCESS"
                Write-Log "Tracing registry update: rmspkg.json" "TRACE"
                Write-Log "Engine registered in metadata database" "DEBUG"
            }
            $global:globalArtifacts = @() # Reset for app
        }
    }
}

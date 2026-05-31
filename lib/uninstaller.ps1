# ---------------------------------------------
# PACKAGE UNINSTALLATION
# Safely removes an installed package: runs hooks, deletes files, cleans metadata.
# HOW IT WORKS:
# 1. Run preUninstall hook (if exists) before any deletion.
# 2. Stage postUninstall hook to temp (because appDir will be deleted).
# 3. Delete artifacts listed in package config (shims, files, directories).
# 4. Delete package directory and metadata.
# 5. Run staged postUninstall hook from temp location.
# 6. Clean up empty parent directories.
# ---------------------------------------------
function Invoke-Uninstallation {
    param($packageConfig)

    $commandName = $packageConfig.commandName
    # Robustness: Force name-based uninstallation path (Enforce Standard)
    $appDir = [System.IO.Path]::GetFullPath((Join-Path $global:ROMs_ROOT $packageConfig.name))

    if (-not $global:AutoConfirm) {
        $confirm = Read-Host "This will delete $appDir and all tracked shims. Proceed? (y/n)"
        if ($confirm.Trim().ToLower() -ne "y") { Write-Log "[ABORTED] Cancelled."; exit 0 }
    }

    Write-Log "Starting uninstallation for $commandName..." "INFO"
    
    # 1. Pre-Uninstall Hook
    $preRel = Get-RomsHookPath -PackageConfig $packageConfig -AppDir $appDir -HookType "preUninstall"
    $preAbs = [System.IO.Path]::GetFullPath((Join-Path $appDir $preRel))
    if (Test-Path $preAbs) {
        Write-Log "Tracing hook discovery: $preRel" "TRACE"
        Invoke-RomsHook -Path $preAbs -ContextName "preUninstall" | Out-Null
    }

    # 2. Stage Post-Uninstall Hook (Persistence)
    # We must copy the postUninstall script to a temp location because $appDir will be deleted.
    $postRel = Get-RomsHookPath -PackageConfig $packageConfig -AppDir $appDir -HookType "postUninstall"
    $postAbs = [System.IO.Path]::GetFullPath((Join-Path $appDir $postRel))
    
    $stagedPostHook = $null
    if (Test-Path $postAbs) {
        $stagedPostHook = Join-Path $env:TEMP "roms_postun_$($packageConfig.name)_$([guid]::NewGuid().ToString().Substring(0,8)).ps1"
        Write-Log "Tracing hook staging: $postRel -> $stagedPostHook" "TRACE"
        Copy-Item $postAbs $stagedPostHook -Force
        Write-Log "Staged postUninstall hook to temp." "DEBUG"
    }

    # Surgical Artifact Removal
    if ($packageConfig.artifacts) {
        Write-Log "Raw Artifacts List: $($packageConfig.artifacts | ConvertTo-Json -Compress)" "RAW"
        foreach ($art in $packageConfig.artifacts) {
            if (Test-Path $art -PathType Leaf) { 
                Write-Log "Tracing artifact removal: $art" "TRACE"
                Remove-Item $art -Force
                Write-Log "Removed artifact: $art" "DEBUG"
            }
        }
    }

    if (Test-Path $appDir) { 
        # Audit Before Purge: Total File-Level Visibility
        Get-ChildItem -Path $appDir -Recurse | ForEach-Object {
            $itemType = if ($_.PSIsContainer) { "directory" } else { "file" }
            Write-Log "Tracing deletion: $($_.FullName) ($itemType)" "TRACE"
        }
        
        Write-Log "Tracing recursive directory removal: $appDir" "TRACE"
        Remove-Item -Path $appDir -Recurse -Force
        Write-Log "Deleted: $appDir" "INFO"
    }

    # 3. Post-Uninstall Hook (Execution)
    if ($stagedPostHook) {
        Write-Log "Tracing post-uninstall execution: $stagedPostHook" "TRACE"
        Invoke-RomsHook -Path $stagedPostHook -ContextName "postUninstall" | Out-Null
        Remove-Item $stagedPostHook -Force # Cleanup temp script
    }

    $meta = Join-Path $global:ROMs_METADATA "$($packageConfig.name).json"
    if (Test-Path $meta) { 
        Write-Log "Raw Metadata before purge: $(Get-Content $meta -Raw)" "RAW"
        Write-Log "Tracing metadata purge: $meta" "TRACE"
        Remove-Item $meta -Force
        Write-Log "Unregistered from database." "INFO"
    }
}

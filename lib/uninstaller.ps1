function Invoke-Uninstallation {
    param($packageConfig)

    $commandName = $packageConfig.commandName
    # Robustness: Force name-based uninstallation path (Enforce Standard)
    $appDir = [System.IO.Path]::GetFullPath((Join-Path $systemRoot $packageConfig.name))

    if (-not $global:AutoConfirm) {
        $confirm = Read-Host "This will delete $appDir and all tracked shims. Proceed? (y/n)"
        if ($confirm.Trim().ToLower() -ne "y") { Write-Log "[ABORTED] Cancelled."; exit 0 }
    }

    Write-Log "Starting uninstallation for $commandName..."
    
    # [FIX]: Support manifest 'hooks' object (preUninstall)
    $hookName = $packageConfig.hooks.preUninstall
    if (!$hookName -and (Test-Path (Join-Path $appDir "rms_uninstall.ps1"))) { $hookName = "rms_uninstall.ps1" }

    if ($hookName) {
        $hookPath = Join-Path $appDir $hookName
        if (Test-Path $hookPath) {
            Write-Log "Running uninstall hook: $hookName"
            & pwsh -File $hookPath 2>&1 | ForEach-Object { Write-Log "  [HOOK] $_" }
            # Uninstallation hooks are usually non-fatal, but we log the exit code
            if ($LASTEXITCODE -ne 0) {
                Write-Log "WARN: Uninstall hook '$hookName' failed with exit code $LASTEXITCODE." "WARN"
            }
        }
    }

    # Surgical Artifact Removal
    if ($packageConfig.artifacts) {
        foreach ($art in $packageConfig.artifacts) {
            if (Test-Path $art -PathType Leaf) { 
                Remove-Item $art -Force
                Write-Log "Removed artifact: $art" 
            }
        }
    }

    if (Test-Path $appDir) { 
        Remove-Item -Path $appDir -Recurse -Force
        Write-Log "Deleted: $appDir" 
    }

    $meta = Join-Path $metadataRoot "$($packageConfig.name).json"
    if (Test-Path $meta) { 
        Remove-Item $meta -Force
        Write-Log "Unregistered from database." 
    }
}

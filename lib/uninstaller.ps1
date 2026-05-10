function Invoke-Uninstallation {
    param($packageConfig)

    $commandName = $packageConfig.commandName
    $installDir = $packageConfig.installDir

    Write-Log "-----------------------------------------------------"
    Write-Log "rmspkg uninstall - $commandName"

    $confirm = Read-Host "This will delete $installDir and all tracked shims. Proceed? (y/n)"
    if ($confirm.Trim().ToLower() -ne "y") { Write-Log "[ABORTED] Cancelled."; exit 0 }

    # Hooks
    $hook = Join-Path $installDir "rms_uninstall.ps1"
    if (Test-Path $hook) { 
        Write-Log "Running uninstall hook..."
        & $hook 2>&1 | ForEach-Object { Write-Log "  [HOOK] $_" } 
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

    if (Test-Path $installDir) { 
        Remove-Item -Path $installDir -Recurse -Force
        Write-Log "Deleted: $installDir" 
    }

    $meta = Join-Path $metadataRoot "$commandName.json"
    if (Test-Path $meta) { 
        Remove-Item $meta -Force
        Write-Log "Unregistered from database." 
    }

    Write-Log "rmspkg: $commandName uninstalled successfully."
    Write-Log "-----------------------------------------------------"
}

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
    $hook = Join-Path $appDir "rms_uninstall.ps1"
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

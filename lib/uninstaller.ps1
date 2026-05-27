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
    
    # 1. Pre-Uninstall Hook
    $preRel = Get-RomsHookPath -PackageConfig $packageConfig -AppDir $appDir -HookType "preUninstall"
    $preAbs = [System.IO.Path]::GetFullPath((Join-Path $appDir $preRel))
    Invoke-RomsHook -Path $preAbs -ContextName "preUninstall" | Out-Null

    # 2. Stage Post-Uninstall Hook (Industrial Strength Persistence)
    # We must copy the postUninstall script to a temp location because $appDir will be deleted.
    $postRel = Get-RomsHookPath -PackageConfig $packageConfig -AppDir $appDir -HookType "postUninstall"
    $postAbs = [System.IO.Path]::GetFullPath((Join-Path $appDir $postRel))
    
    $stagedPostHook = $null
    if (Test-Path $postAbs) {
        $stagedPostHook = Join-Path $env:TEMP "roms_postun_$($packageConfig.name)_$([guid]::NewGuid().ToString().Substring(0,8)).ps1"
        Copy-Item $postAbs $stagedPostHook -Force
        Write-Log "Staged postUninstall hook to temp."
    }

    # Surgical Artifact Removal 
    if ($packageConfig.artifacts) {
        foreach ($art in $packageConfig.artifacts) {
            if ($art.StartsWith("env:")) {
                $envKey = $art.Substring(4)
                Invoke-RomsEnvironmentRemove -Key $envKey
            } elseif (Test-Path $art -PathType Leaf) { 
                Remove-Item $art -Force
                Write-Log "Removed artifact: $art" 
            }
        }
    }

    if (Test-Path $appDir) { 
        Remove-Item -Path $appDir -Recurse -Force
        Write-Log "Deleted: $appDir" 
    }

    # 3. Post-Uninstall Hook (Execution)
    if ($stagedPostHook) {
        Invoke-RomsHook -Path $stagedPostHook -ContextName "postUninstall" | Out-Null
        Remove-Item $stagedPostHook -Force # Cleanup temp script
    }

    $meta = Join-Path $metadataRoot "$($packageConfig.name).json"
    if (Test-Path $meta) { 
        Remove-Item $meta -Force
        Write-Log "Unregistered from database." 
    }
}

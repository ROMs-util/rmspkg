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
    # Containment: the package name is attacker-controlled manifest data, so it is
    # validated as a plain identifier (no path separators, no "..") and the joined
    # path is asserted to stay inside ROMs_ROOT before any deletion can occur.
    $appDir = Assert-PathWithinRoot -Path (Join-Path $global:ROMs_ROOT (Get-SafeName $packageConfig.name)) -Root $global:ROMs_ROOT

    if (-not $global:AutoConfirm) {
        $confirm = Read-Host "This will delete $appDir and all tracked shims. Proceed? (y/n)"
        if ($confirm.Trim().ToLower() -ne "y") { Write-Log "[ABORTED] Cancelled."; exit 0 }
    }

    Write-Log "Starting uninstallation for $commandName..." "INFO"
    
    # 1. Pre-Uninstall Hook
    $preRel = Get-RomsHookPath -PackageConfig $packageConfig -AppDir $appDir -HookType "preUninstall"
    # Containment: the hook relative path is attacker-controlled manifest data, so
    # it is validated (no "..", drive, UNC, or ADS) and resolved strictly inside
    # $appDir before it is handed to pwsh.
    $preAbs = Get-SafeRelativePath -Relative $preRel -Root $appDir
    if (Test-Path $preAbs) {
        Write-Log "Tracing hook discovery: $preRel" "TRACE"
        Invoke-RomsHook -Path $preAbs -ContextName "preUninstall" | Out-Null
    }

    # 2. Stage Post-Uninstall Hook (Persistence)
    # We must copy the postUninstall script to a temp location because $appDir will be deleted.
    $postRel = Get-RomsHookPath -PackageConfig $packageConfig -AppDir $appDir -HookType "postUninstall"
    # Containment: same guard as the pre-uninstall hook; the staged post-uninstall
    # hook is copied from this resolved path, so it must stay inside $appDir.
    $postAbs = Get-SafeRelativePath -Relative $postRel -Root $appDir
    
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
            # Environment artifacts are scope markers ("env:KEY"), not file paths.
            # They MUST short-circuit before the file containment check: "env:" is a
            # real PowerShell drive so Test-Path would pass, and the colon then makes
            # GetFullPath throw. Delegation to the orchestrator handles both scopes.
            if ($art.StartsWith("env:")) {
                Invoke-RomsEnvironmentRemove -Key $art.Substring(4)
            } elseif (Test-Path $art -PathType Leaf) {
                # Containment: an artifact is attacker-controlled manifest data, so
                # it must resolve to a descendant of $appDir or $global:ROMs_BIN (the
                # two places the engine legitimately writes: package files and shared
                # command shims). A relative artifact resolves under $appDir first.
                # The check is done silently against both roots here (not via the
                # logging Assert-PathWithinRoot) so a rejection produces exactly one
                # [ERROR] line per the Log-Only Error Abort rule.
                $artResolved = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($art)) { $art } else { Join-Path $appDir $art }))
                $inApp = ($artResolved -eq $appDir) -or $artResolved.StartsWith($appDir + '\', [System.StringComparison]::OrdinalIgnoreCase)
                $inBin = ($artResolved -eq $global:ROMs_BIN) -or $artResolved.StartsWith($global:ROMs_BIN + '\', [System.StringComparison]::OrdinalIgnoreCase)
                if (-not ($inApp -or $inBin)) {
                    Write-Log "Artifact '$art' escapes both app and bin roots; removal aborted" "ERROR"
                    throw [System.Security.SecurityException]::new("containment")
                }

                Write-Log "Tracing artifact removal: $artResolved" "TRACE"
                Remove-Item $artResolved -Force
                Write-Log "Removed artifact: $artResolved" "DEBUG"
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
        Invoke-RomsHook -Path $stagedPostHook -ContextName "postUninstall" -AllowStaged | Out-Null
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

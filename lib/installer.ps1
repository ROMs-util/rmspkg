function Invoke-Installation {
    param($packageConfig, $isRmsPackage, $packagePath, $sourceDir, [switch]$noShim)

    $rollbackNeeded = $false
    $createdDir = $false
    $commandName = $packageConfig.commandName
    
    # Robustness: Force absolute, name-based installation paths (Enforce Standard)
    $appDir = [System.IO.Path]::GetFullPath((Join-Path $systemRoot $packageConfig.name))

    try {
        Check-RomsDependencies $packageConfig.dependencies

        # 1. Surgical Hook Extraction (Pre-Check)
        if ($isRmsPackage) {
            if (-not (Test-Path $appDir)) { New-Item -ItemType Directory -Path $appDir -Force | Out-Null; $createdDir = $true; $rollbackNeeded = $true }
            
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
            try {
                $preRel = Get-RomsHookPath -PackageConfig $packageConfig -AppDir $appDir -HookType "preInstall"
                # Normalize slashes for ZIP lookup
                $preRelNormalized = $preRel.Replace("/", "\")
                $e = $zip.Entries | Where-Object { $_.FullName -eq $preRelNormalized }
                if ($e) {
                    $d = [System.IO.Path]::GetFullPath((Join-Path $appDir $preRel))
                    $p = Split-Path $d
                    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $d, $true)
                    Write-Log "Pre-extracted hook: $preRel"
                }
            } finally { $zip.Dispose() }
        }

        # 2. Pre-Install Hook
        $preRel = Get-RomsHookPath -PackageConfig $packageConfig -AppDir $appDir -HookType "preInstall"
        $preAbs = [System.IO.Path]::GetFullPath((Join-Path $appDir $preRel))
        $res = Invoke-RomsHook -Path $preAbs -ContextName "preInstall"
        if ($res -and $res -ne 0) { throw "preInstall hook failed." }

        if (-not (Test-Path $appDir)) {
            New-Item -ItemType Directory -Path $appDir -ErrorAction Stop | Out-Null
            $createdDir = $true; $rollbackNeeded = $true
            Write-Log "Created directory: $appDir"
        }

        if ($isRmsPackage) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
            try {
                # [FEATURE]: Industrial Strength Extraction (Auto-include hooks)
                $pack = @($packageConfig.files) + @("roms_package.json")
                $allHookTypes = @("preInstall", "postInstall", "preUninstall", "postUninstall")
                foreach ($ht in $allHookTypes) {
                    $pack += Get-RomsHookPath -PackageConfig $packageConfig -AppDir $appDir -HookType $ht
                }

                foreach ($f in ($pack | Select-Object -Unique)) {
                    # Normalize slashes for ZIP lookup
                    $fNormalized = $f.Replace("/", "\")
                    $e = $zip.Entries | Where-Object { $_.FullName -eq $fNormalized }
                    if ($e) {
                        $d = [System.IO.Path]::GetFullPath((Join-Path $appDir $f))
                        $p = Split-Path $d
                        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
                        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $d, $true)
                        Write-Log "Extracted: $f"
                    }
                }
            } finally { $zip.Dispose() }
        } else {
            foreach ($f in (@($packageConfig.files) + @("roms_package.json"))) {
                $s = Join-Path $sourceDir $f; $d = Join-Path $appDir $f
                if ($s -ne $d) { Copy-Item $s $d -Force -ErrorAction Stop; Write-Log "Copied: $f" }
            }
        }

        # Create Shim (Force absolute path resolution for executable)
        $exec = $packageConfig.executable
        if ($exec -and -not [System.IO.Path]::IsPathRooted($exec)) {
            $exec = [System.IO.Path]::GetFullPath((Join-Path $appDir $exec))
        }

        if (-not $exec) { 
            $exec = [System.IO.Path]::GetFullPath((Join-Path $appDir "$commandName.bat"))
            if (-not (Test-Path $exec)) { 
                $exec = [System.IO.Path]::GetFullPath((Join-Path $appDir "$commandName.ps1")) 
            } 
        }
        if (-not $noShim) { Create-Shim $commandName $exec }

        # Register metadata
        $final = $packageConfig
        # Ensure absolute path is persisted
        $final.executable = $exec
        
        # Industrial Strength: Audit Trail (Persist hash if provided by manager)
        if ($global:ROMs_STAGED_HASH) {
            $final | Add-Member -MemberType NoteProperty -Name "sha256" -Value $global:ROMs_STAGED_HASH -Force
        }

        if ($global:globalArtifacts.Count -gt 0) { 
            $final | Add-Member -MemberType NoteProperty -Name "artifacts" -Value $global:globalArtifacts -Force 
        }

        # Apply Environment Variables (Industrial Strength)
        if ($packageConfig.environment_variables) {
            Invoke-RomsEnvironmentSet -Variables $packageConfig.environment_variables
        }

        # Re-sync artifacts if they were modified by Invoke-RomsEnvironmentSet
        if ($null -eq $final.artifacts) {
            $final | Add-Member -MemberType NoteProperty -Name "artifacts" -Value $global:globalArtifacts -Force
        } else {
            $final.artifacts = $global:globalArtifacts
        }

        $final | ConvertTo-Json -Depth 10 | Out-File (Join-Path $metadataRoot "$($packageConfig.name).json") -Encoding utf8
        if (-not $noShim) { Write-Log "Registered with $($global:globalArtifacts.Count) artifacts." }

        # 2. Post-Install Hook
        $postRel = Get-RomsHookPath -PackageConfig $packageConfig -AppDir $appDir -HookType "postInstall"
        $postAbs = [System.IO.Path]::GetFullPath((Join-Path $appDir $postRel))
        $res = Invoke-RomsHook -Path $postAbs -ContextName "postInstall"
        if ($res -and $res -ne 0) { throw "postInstall hook failed." }

        $rollbackNeeded = $false
        return $appDir # Return the installation directory
    } catch {
        Write-Log "ERROR: $_" "ERROR"
        if ($rollbackNeeded) {
            if ($createdDir) { Remove-Item $appDir -Recurse -Force }
            # [FIX]: Use package name for metadata cleanup, not commandName
            $m = Join-Path $metadataRoot "$($packageConfig.name).json"
            if (Test-Path $m) { Remove-Item $m -Force }
        }
        throw $_
    }
}

function Find-PackageExecutables {
    param(
        [string]$AppDirectory
    )

    $executables = @()
    $executableExtensions = @(".exe", ".cmd", ".ps1", ".bat")
    $excludedFileNames = @("rms_install.ps1", "rms_uninstall.ps1")

    Get-ChildItem -Path $AppDirectory -File -Recurse | ForEach-Object {
        $file = $_
        if ($executableExtensions -contains $file.Extension.ToLower()) {
            # Exclude specific internal scripts
            if ($excludedFileNames -notcontains $file.Name.ToLower()) {
                $executables += $file.FullName
            }
        }
    }
    return $executables
}

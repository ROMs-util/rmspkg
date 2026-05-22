function Invoke-Installation {
    param($packageConfig, $isRmsPackage, $packagePath, $sourceDir, [switch]$noShim)

    $rollbackNeeded = $false
    $createdDir = $false
    $commandName = $packageConfig.commandName
    
    # Robustness: Force absolute, name-based installation paths (Enforce Standard)
    $appDir = [System.IO.Path]::GetFullPath((Join-Path $systemRoot $packageConfig.name))

    try {
        Check-RomsDependencies $packageConfig.dependencies

        if (-not (Test-Path $appDir)) {
            New-Item -ItemType Directory -Path $appDir -ErrorAction Stop | Out-Null
            $createdDir = $true; $rollbackNeeded = $true
            Write-Log "Created directory: $appDir"
        }

        if ($isRmsPackage) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
            try {
                $pack = @($packageConfig.files) + @("roms_package.json")
                foreach ($f in $pack) {
                    $e = $zip.Entries | Where-Object { $_.FullName -eq $f }
                    if ($e) {
                        $d = Join-Path $appDir $f
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
        $final | ConvertTo-Json -Depth 10 | Out-File (Join-Path $metadataRoot "$($packageConfig.name).json") -Encoding utf8
        if (-not $noShim) { Write-Log "Registered with $($global:globalArtifacts.Count) artifacts." }

        # Post Hook
        $post = Join-Path $appDir "rms_install.ps1"
        if (Test-Path $post) { 
            Write-Log "Running install hook..."
            & $post 2>&1 | ForEach-Object { Write-Log "  [HOOK] $_" } 
        }

        $rollbackNeeded = $false
        return $appDir # Return the installation directory
    } catch {
        Write-Log "ERROR: $_" "ERROR"
        if ($rollbackNeeded) {
            if ($createdDir) { Remove-Item $appDir -Recurse -Force }
            $m = Join-Path $metadataRoot "$commandName.json"; if (Test-Path $m) { Remove-Item $m -Force }
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

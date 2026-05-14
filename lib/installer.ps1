function Invoke-Installation {
    param($packageConfig, $isRmsPackage, $packagePath, $sourceDir, [switch]$noShim)

    $rollbackNeeded = $false
    $createdDir = $false
    $commandName = $packageConfig.commandName
    $installDir = $packageConfig.installDir

    try {
        Check-RomsDependencies $packageConfig.dependencies

        if (-not (Test-Path $installDir)) {
            New-Item -ItemType Directory -Path $installDir -ErrorAction Stop | Out-Null
            $createdDir = $true; $rollbackNeeded = $true
            Write-Log "Created directory: $installDir"
        }

        if ($isRmsPackage) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
            try {
                $pack = @($packageConfig.files) + @("roms_package.json")
                foreach ($f in $pack) {
                    $e = $zip.Entries | Where-Object { $_.FullName -eq $f }
                    if ($e) {
                        $d = Join-Path $installDir $f
                        $p = Split-Path $d
                        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
                        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $d, $true)
                        Write-Log "Extracted: $f"
                    }
                }
            } finally { $zip.Dispose() }
        } else {
            foreach ($f in (@($packageConfig.files) + @("roms_package.json"))) {
                $s = Join-Path $sourceDir $f; $d = Join-Path $installDir $f
                if ($s -ne $d) { Copy-Item $s $d -Force -ErrorAction Stop; Write-Log "Copied: $f" }
            }
        }

        # Create Shim
        $exec = $packageConfig.executable
        if (-not $exec) { 
            $exec = Join-Path $installDir "$commandName.bat"
            if (-not (Test-Path $exec)) { $exec = Join-Path $installDir "$commandName.ps1" } 
        }
        if (-not $noShim) { Create-Shim $commandName $exec }

        # Register metadata
        $final = $packageConfig
        if ($global:globalArtifacts.Count -gt 0) { 
            $final | Add-Member -MemberType NoteProperty -Name "artifacts" -Value $global:globalArtifacts -Force 
        }
        $final | ConvertTo-Json -Depth 10 | Out-File (Join-Path $metadataRoot "$commandName.json") -Encoding utf8
        if (-not $noShim) { Write-Log "Registered with $($global:globalArtifacts.Count) artifacts." }

        # Post Hook
        $post = Join-Path $installDir "rms_install.ps1"
        if (Test-Path $post) { 
            Write-Log "Running install hook..."
            & $post 2>&1 | ForEach-Object { Write-Log "  [HOOK] $_" } 
        }

        $rollbackNeeded = $false
        return $installDir # Return the installation directory
    } catch {
        Write-Log "ERROR: $_" "ERROR"
        if ($rollbackNeeded) {
            if ($createdDir) { Remove-Item $installDir -Recurse -Force }
            $m = Join-Path $metadataRoot "$commandName.json"; if (Test-Path $m) { Remove-Item $m -Force }
        }
        throw $_
    }
}

function Find-PackageExecutables {
    param(
        [string]$InstallDirectory
    )

    $executables = @()
    $executableExtensions = @(".exe", ".cmd", ".ps1", ".bat")
    $excludedFileNames = @("rms_install.ps1", "rms_uninstall.ps1")

    Get-ChildItem -Path $InstallDirectory -File -Recurse | ForEach-Object {
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

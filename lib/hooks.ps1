# hooks.ps1 - Lifecycle Hook Management

# ---------------------------------------------
# HOOK PATH RESOLUTION
# Resolves the relative path to a lifecycle hook script.
# HOW IT WORKS:
# 1. Check manifest ($PackageConfig.hooks.$HookType) for explicit path.
# 2. Fall back to standard kebab-case naming: pre-install.ps1, post-install.ps1, etc.
# Returns: Relative path string to the hook script.
# ---------------------------------------------
function Get-RomsHookPath {
    param(
        [Parameter(Mandatory=$true)]$PackageConfig,
        [Parameter(Mandatory=$true)][string]$AppDir,
        [Parameter(Mandatory=$true)][ValidateSet("preInstall", "postInstall", "preUninstall", "postUninstall")][string]$HookType
    )

    # 1. Check Manifest (Explicit Standard - Trinity v1.1.0)
    if ($PackageConfig.hooks) {
        $nameFromManifest = $PackageConfig.hooks.$HookType
        if ($nameFromManifest) {
            return $nameFromManifest # Return relative path
        }
    }

    # 2. Check Fallback (Kebab-Case Standard)
    $standardName = ""
    switch ($HookType) {
        "preInstall"    { $standardName = "pre-install.ps1" }
        "postInstall"   { $standardName = "post-install.ps1" }
        "preUninstall"  { $standardName = "pre-uninstall.ps1" }
        "postUninstall" { $standardName = "post-uninstall.ps1" }
    }
    
    return $standardName
}

# ---------------------------------------------
# HOOK SCRIPT EXECUTION
# Runs a lifecycle hook script with proper environment isolation.
# HOW IT WORKS:
# 1. Check if hook file exists at given path.
# 2. Execute via pwsh (PowerShell Core) with -NoProfile for clean environment.
# 3. Capture stdout/stderr and log each line.
# 4. Return exit code (0 = success, non-zero = failure), or $null if no hook.
# ---------------------------------------------
function Invoke-RomsHook {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ContextName # e.g. "postInstall"
    )

    if (Test-Path $Path) {
        Write-Log "Running hook: $ContextName ($($Path | Split-Path -Leaf))" "INFO"
        
        # Execute via pwsh to ensure clean environment and exit code capture
        & pwsh -NoProfile -File $Path 2>&1 | ForEach-Object { Write-Log "  [HOOK] $_" }
        
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            Write-Log "Hook '$ContextName' failed with exit code $exitCode." "ERROR"
            return $exitCode
        }
        return 0
    }
    
    return $null # Hook file not present
}

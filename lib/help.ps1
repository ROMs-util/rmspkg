function Show-Help {
    param([string]$invokedAs)

    # 1. Resolve Execution Context (Portable vs System)
    if (-not $invokedAs) {
        $invokedAs = if ($PSScriptRoot -notlike "*C:\roms*") { ".\rmspkg.bat" } else { "rmspkg" }
    }

    # 2. Header
    Write-Host "`n----- ${invokedAs}: Standalone Package Engine -----" -ForegroundColor Cyan
    Write-Host "Low-level engine for the ROMs-util ecosystem. Handles atomic package lifecycle.`n"
    
    # 3. Usage & Commands
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  $invokedAs <command> [input] [options]`n"
    
    Write-Host "COMMANDS:" -ForegroundColor Yellow
    $c = "  {0,-18} {1}"
    Write-Host ($c -f "install <path>",  "Extract and register an .rms package or project folder.")
    Write-Host ($c -f "uninstall <name>", "Cleanly remove files, shims, and metadata records.")
    Write-Host ($c -f "bootstrap",        "Self-register engine and install global launchers.")
    Write-Host ($c -f "help",             "Display this technical documentation.`n")
    
    # 4. Global Options (Bilingual)
    Write-Host "OPTIONS:" -ForegroundColor Yellow
    $o = "  {0,-18} {1}"
    Write-Host ($o -f "-y, --yes",         "Non-interactive mode; assume 'yes' to all prompts.")
    Write-Host ($o -f "-v, --verbose",     "Diagnostic output (-v: DEBUG, -vv: TRACE, -vvv: RAW).")
    Write-Host ($o -f "--no-shim",         "Bypass shim creation (Managed by High-level Manager).`n")
    
    # 5. Infrastructure Paths
    Write-Host "SYSTEM PATHS:" -ForegroundColor Yellow
    $p = "  {0,-12} {1}"
    Write-Host ($p -f "Root:",     $global:ROMS_ROOT)
    Write-Host ($p -f "Metadata:", $global:METADATA_DIR)
    Write-Host ($p -f "Binaries:", $global:BIN_DIR)
    Write-Host ($p -f "Logs:",     $global:LOG_DIR)
    

    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  $invokedAs install .\package.rms -vv"
    Write-Host "  $invokedAs uninstall myapp -y"
    Write-Host "`n-----------------------------------------------------`n"
}

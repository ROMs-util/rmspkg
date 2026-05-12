function Show-Help {
    param([string]$invokedAs)

    # Resolve Context
    $invokedAs = if ($PSScriptRoot -notlike "*C:\roms*") { ".\rmspkg.bat" } else { "rmspkg" }

    Write-Host ""
    Write-Host "----- ${invokedAs}: Official ROMs-util Package Engine -----" -ForegroundColor Cyan
    Write-Host "The official standalone engine for the .rms ecosystem."
    Write-Host ""
    
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  $invokedAs <command> [target]"
    Write-Host ""

    Write-Host "COMMANDS:" -ForegroundColor Yellow
    Write-Host "  install <path>     Install from an .rms file or folder."
    Write-Host "  uninstall <name>   Remove an installed package by its command name."
    Write-Host "  help               Show this menu."
    Write-Host ""

    Write-Host "SYSTEM PATHS:" -ForegroundColor Yellow
    Write-Host "  Root:    $systemRoot"
    Write-Host "  Bin:     $binRoot (Command Launchers)"
    Write-Host "  Logs:    $logRoot"
    Write-Host ""

    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  Install:   $invokedAs install .\myapp.rms"
    Write-Host "  Uninstall: $invokedAs uninstall myapp"
    Write-Host ""
    
    Write-Host "Note: Administrator privileges are only required for installation/removal."
    Write-Host "-----------------------------------------------------"
    Write-Host ""
}

function Show-Help {
    param([string]$invokedAs)

    # Resolve Context
    $invokedAs = if ($PSScriptRoot -notlike "*C:\roms*") { ".\rmspkg.bat" } else { "rmspkg" }

    Write-Host ""
    Write-Host "----- ${invokedAs}: Official ROMs-util Package Engine -----" -ForegroundColor Cyan
    Write-Host "The official standalone engine for the .rms ecosystem."
    Write-Host ""
    
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  $invokedAs <path|name> [options]"
    Write-Host ""

    Write-Host "OPTIONS:" -ForegroundColor Yellow
    Write-Host "  <path|name>        Path to an .rms/folder OR name of an installed app."
    Write-Host "  --uninstall        Switch to uninstallation mode."
    Write-Host "  --help             Show this menu."
    Write-Host ""

    Write-Host "SYSTEM PATHS:" -ForegroundColor Yellow
    Write-Host "  Root:    C:\roms"
    Write-Host "  Bin:     C:\roms\bin (Command Launchers)"
    Write-Host "  Logs:    C:\roms\logs"
    Write-Host ""

    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  Install:   $invokedAs .\myapp.rms"
    Write-Host "  Uninstall: $invokedAs --uninstall myapp"
    Write-Host ""
    
    Write-Host "Note: Administrator privileges are only required for installation/removal."
    Write-Host "-----------------------------------------------------"
    Write-Host ""
}

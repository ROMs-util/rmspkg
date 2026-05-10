function Show-Help {
    param([string]$invokedAs)

    Write-Host ""
    Write-Host "----- ${invokedAs}: Official ROMs-util Package Engine -----" -ForegroundColor Cyan
    Write-Host "A robust, standalone engine for managing the .rms ecosystem."
    Write-Host ""
    
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  $invokedAs <path> [options]"
    Write-Host ""

    Write-Host "OPTIONS:" -ForegroundColor Yellow
    Write-Host "  <path>             Path to an .rms file or a local project folder."
    Write-Host "  -config <path>     Manually specify a roms_package.json location."
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
    Write-Host "  Local:     $invokedAs .\my-project-folder"
    Write-Host "  Cleanup:   $invokedAs -config C:\roms\.metadata\app.json --uninstall"
    Write-Host ""
    
    Write-Host "Note: Administrator privileges are only required for installation/removal."
    Write-Host "-----------------------------------------------------"
    Write-Host ""
}

# ROMs Package Engine (`rmspkg`)

> The low-level standalone engine and "Physics" layer of the ROMs ecosystem.

`rmspkg` is the heavy-lifting component responsible for the actual installation, extraction, and lifecycle management of applications. It is designed to be fully standalone, allowing users to manage packages even without the high-level `roms` manager.

---

## 👤 User Guide
This guide is for users who prefer using the low-level engine directly or are operating in a standalone environment.

### 1. Standalone Power
Unlike most package managers, `rmspkg` does not require a remote registry to function. It can install any valid `.rms` package or project folder directly.

### 2. Global Flags
These flags work with all commands:

| Flag | Alias | Description |
| :--- | :--- | :--- |
| `-y` | `--yes` | Skip confirmation prompts (AutoConfirm). |
| `-v` | `--verbose` | Enable verbose debug logging. |
| `-vv` | | Very verbose (shows TRACE messages). |
| `-vvv` | | Raw output (shows RAW messages). |
| `-h` | `--help` | Show help for the command. |

### 3. Common Commands

| Command | Description |
| :--- | :--- |
| `rmspkg <path>` | Install a local `.rms` file or project folder. |
| `rmspkg uninstall <name>` | Remove an installed package by its name. |
| `rmspkg bootstrap` | Install or repair the standalone engine to system root. |
| `rmspkg help` | Show the standalone help menu. |

### 4. Troubleshooting
- **Logs:** Every installation has its own dedicated log file at `C:\roms\logs\<package_name>.log`.
- **Integrity Errors:** If an installation fails, `rmspkg` automatically attempts an atomic rollback to leave your system clean. Check the logs for "ROLLBACK" messages.
- **Elevation Required:** Most operations require Administrator privileges. Run PowerShell as Administrator.
- **Missing Engine:** If `rmspkg` is not found in PATH, run `rmspkg bootstrap` to self-install.

### 5. Examples
```powershell
# Install from local .rms file
rmspkg C:\Downloads\package-v1.0.0.rms

# Install from project folder
rmspkg C:\Projects\my-app

# Install with verbose output
rmspkg C:\Downloads\package-v1.0.0.rms -vvv

# Skip confirmation prompt
rmspkg C:\Downloads\package-v1.0.0.rms -y

# Uninstall a package
rmspkg uninstall my-package

# Repair/install engine to system root
rmspkg bootstrap

# Show help
rmspkg help
```

---

## 🛠️ Developer Guide
This guide is for developers building packages or contributing to the engine core.

### 1. Architecture: The Physics Layer
`rmspkg` handles the "Physics" of the ecosystem:

- **Router:** `rmspkg.ps1` handles argument parsing and command routing.
- **Core:** `lib/core.ps1` manages global constants, colorized logging, and dependency checking.
- **Installer:** `lib/installer.ps1` handles the atomic installation lifecycle.
- **Uninstaller:** `lib/uninstaller.ps1` handles safe package removal.
- **Hooks:** `lib/hooks.ps1` manages lifecycle hooks (pre-install, post-install, etc.).
- **Environment:** `lib/environment.ps1` handles shim creation and PATH updates.
- **Bootstrap:** `lib/bootstrap.ps1` handles self-installation and engine recovery.
- **Help:** `lib/help.ps1` provides CLI help display.

### 2. Transactional Integrity
The engine follows a strict **Try/Catch/Rollback** pattern:

1. **Validation:** Checks system dependencies and manifest integrity using the Truth-Verification Watchdog.
2. **Extraction:** Files are unpacked to the standardized application folder in `C:\roms`.
3. **Registration:** Metadata and artifacts (like shims) are recorded.
4. **Hooks:** System-level OS hooks are executed using the Hybrid Standard (Manifest-First or Fallback).
5. **Rollback:** If *any* step above fails, the engine deletes the partial installation and unregisters the metadata.

### 3. Module Dependency Flow
```
rmspkg.ps1 (Router)
    |
    +---> lib/core.ps1 (Write-Log, Check-RomsDependencies, Confirm-Elevation)
    |
    +---> lib/installer.ps1 (Invoke-Installation, Find-PackageExecutables)
    |         |
    |         +---> lib/hooks.ps1 (Get-RomsHookPath, Invoke-RomsHook)
    |         +---> lib/environment.ps1 (Create-Shim, Update-EnvironmentPath)
    |
    +---> lib/uninstaller.ps1 (Invoke-Uninstallation)
    |         |
    |         +---> lib/hooks.ps1 (Get-RomsHookPath, Invoke-RomsHook)
    |
    +---> lib/bootstrap.ps1 (Invoke-SelfBootstrap)
    |
    +---> lib/help.ps1 (Show-Help)
```

### 4. Environment Variables
| Variable | Description | Default |
| :--- | :--- | :--- |
| `ROMs_ROOT` | Ecosystem root directory | `C:\roms` |
| `ROMs_BIN` | Command shims directory | `C:\roms\bin` |
| `ROMs_METADATA` | Package metadata registry | `C:\roms\.metadata` |
| `ROMs_LOGS` | Log files directory | `C:\roms\logs` |
| `ROMs_TEMP` | Temporary workspace | `C:\roms\temp` |

### 5. .NET Rule
To ensure version independence and maximum reliability, `rmspkg` avoids high-level PowerShell cmdlets for core tasks. It uses native .NET namespaces for:
- **Hashing:** `System.Security.Cryptography.SHA256`
- **Compression:** `System.IO.Compression.ZipFile`
- **File I/O:** `System.IO.File` and `System.IO.Directory`

### 6. Building Packages
To create a package compatible with this engine, use the **`rms-builder`** tool. Ensure your `roms_package.json` follows the Trinity v1.1.0 standard.

### 7. Contributing
1. Add new functions to the appropriate module in `lib/`.
2. Add comprehensive comments explaining HOW IT WORKS.
3. Export the function from the main `rmspkg.ps1` if it's a new command.
4. Test with `-vvv` flag to verify RAW output logging.
5. Update this README if adding new commands or changing architecture.

---

## 📚 See Also
- [ROMs Package Manager](https://github.com/ROMs-util/roms/blob/main/README.md)
- [Package Builder](https://github.com/ROMs-util/rms-builder/blob/main/README.md)
- [ROMs-util Documentation](https://github.com/ROMs-util/roms-docs/blob/main/README.md)

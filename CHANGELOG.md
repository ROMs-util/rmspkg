# Changelog - rmspkg (Package Installer)

All notable changes to the `rmspkg` standalone engine will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- **Shared containment guards**: new `lib/safety.ps1` module providing `Get-SafeName` (strict identifier allowlist), `Assert-PathWithinRoot`, and `Get-SafeRelativePath` (rejects `..` traversal, drive letters, UNC prefixes, and Alternate Data Stream names). All manifest-driven path sinks now route through this single module.
- **CMD metacharacter escaping for shims**: `Get-CmdEscapedPath` in `lib/environment.ps1` caret-escapes `& | < >` (and literal `^`) in the executable path embedded in generated `.bat` shims, so a crafted manifest cannot inject commands into a launched shim.

### Security
- **Package name validation**: the manifest `name` is validated against the identifier allowlist before it composes the install root, blocking `..` traversal and absolute-path values.
- **Per-package log path containment**: `rmspkg.ps1` validates the name through `Get-SafeName` before composing `C:\roms\logs\<name>.log` on both install and uninstall, so an attacker-controlled manifest name can no longer plant a log file outside the logs directory.
- **File extraction containment**: every manifest `files[]` entry is resolved through `Get-SafeRelativePath` against the app directory before `ExtractToFile` writes it.
- **Hook extraction and execution containment**: manifest hook paths (`preInstall`, `postInstall`, `preUninstall`, `postUninstall`) are validated relative to the app directory before extraction, and hook execution passes through a root-containment check before invoking `pwsh` (the legitimately staged post-uninstall copy is the sole explicit exception).
- **Uninstall artifact containment**: stored artifact entries are checked against the sandbox roots (app directory or managed bin) before deletion; an escaping artifact aborts the uninstall with a single logged error.
- **Bootstrap copy validation**: engine library filenames are validated as plain leaf names before being joined into the destination path during self-registration.
- **Dependency identifier validation**: dependency tokens are passed through `Get-SafeName` before metadata lookups, closing the same trust-boundary gap on the dependency list.
- **Elevation argument hardening**: the UAC relaunch builds its argument list from discrete tokens instead of a concatenated string, so paths containing spaces or metacharacters cannot inject extra flags into the elevated process.

### Fixed
- **Environment variable orchestration restored**: `lib/environment.ps1` — reinstated `Invoke-RomsEnvironmentSet` / `Invoke-RomsEnvironmentRemove` (collaterally removed during a logging refactor while `installer.ps1` still called them, crashing any package that declares `environment_variables`) and the matching `env:<KEY>` artifact branch in `lib/uninstaller.ps1`. Machine-scope writes fall back to User scope with a warning when the session is not elevated; removal clears both scopes and deletes the value properly (no ghost empty entry).
- **Uninstall artifact path parse error**: the artifact containment resolution used a bare `if` expression that PowerShell parsed as a command; corrected to a subexpression.
- **Fatal errors now persist to disk**: the engine's fatal paths ("Could not identify package", "Installation failed", "Unknown command", missing dependency, hook rejections) were written to the raw error stream and lost when stdout was redirected; they now go through the dual-target logger into the on-disk log.
- **Rollback purges environment variables**: `lib/installer.ps1` — a failed post-install hook now clears every environment variable the install had already applied before re-throwing the original error. Previously the rollback deleted the app directory and metadata while the variables stayed in the registry with no artifact record, orphaning them permanently.
- **Rollback purges command shims too**: `lib/installer.ps1` — the rollback artifact sweep now removes every tracked artifact of the failed transaction, not just environment markers, so a rolled-back install can no longer leave a launcher stub in the managed bin directory pointing at files that were deleted.
- **Duplicate error lines removed**: containment rejections previously emitted the same message twice (throw string + log line). The guard layer now logs the descriptive reason exactly once and aborts with a message-less sentinel that callers recognize and do not re-log.

## [0.1.0-beta.2] - 2026-09-06
### Fixed
- **Package Dependency Parsing**: `lib/core.ps1` — Fixed missing handling for the `dependencies.packages` property in `Check-RomsDependencies`, ensuring dependencies declared under the Trinity v1.1 schema are properly validated before installation.

## [v0.1.0-beta.1] - 2026-09-06
### Fixed
- **Mirror Pipe Banner Visibility**:
  - Fixed a bug where the engine's success/uninstall banners (`[SUCCESS] ... installed/uninstalled.`) and the raw JSON handshake output were invisible when `roms install pkg:>constraint` triggered Mirror Pipe mode. CMD redirected stdout to a trash file, and the engine's `Write-Host` calls were being swallowed along with it.
  - Applied the Mirror Pipe Standard (established in `fix#58`) to `rmspkg.ps1`: all three `Write-Host` banner blocks (install, uninstall, raw JSON) now check `$global:Roms_MirrorLogs` and route through `[Console]::Error.WriteLine()` with ANSI escape sequences when mirroring is active, falling back to `Write-Host` in normal mode.

## [d8b157c] - 2026-06-14
### Added
- **Mirror Pipe Standard (Standalone Fidelity)**:
  - Ported the Mirror Pipe architecture to the standalone engine, enabling logs to bypass stdout redirection via ANSI-colored Stderr.
  - Implemented hardcoded ANSI escape sequences in `Write-Log` to maintain UI colors even when `Write-Host` is suppressed by the shell.
- **Log Handshake Protocol**:
  - Added support for the `--mirror` flag to allow the high-level manager to synchronize redirection states.
  - Standardized the global redirection state variable to `$global:Roms_MirrorLogs`.


---

## [v0.1.0-alpha] - 2026-05-31
### Added
- **Industrial Diagnostic Standardization**:
  - **RAW Standard:** Implemented dual-target formatting. Level 3 (RAW) now provides **Pretty-Printed Magenta** JSON in the console for human Architects while maintaining **Tight-Inline** compressed strings in log files for machine auditing.
  - **File-by-File Physical Truth:** Upgraded Level 2 (TRACE) to provide granular visibility. The engine now logs every individual file copy, extraction, and deletion as a unique event.
  - **Anti-Ghost Audit:** All diagnostic logs are now physically verified via `Test-Path` before emission, ensuring logs reflect physical truth rather than just code-flow intent.
  - **Variable Purity:** Standardized all global variables to use the **`$global:ROMs_`** prefix and purged legacy/double-underscore variants.
- **Machine Handshake Protocol**:
  - Implemented the **File Handshake**: the engine now writes a temporary `handshake.json` report to `C:\roms\temp\`, allowing the Manager to receive 100% accurate installation data without polluting the user's console stream.
- **Robustness**:
  - Introduced **Audit Before Purge** pattern: the engine now recursively audits all items being destroyed during uninstallation before directory removal.
  - Hardened argument parsing using array sub-expressions `@($args | ...)` to prevent null-indexing crashes.


### Changed
- **Honest Diagnostics:** Eliminated "Ghost Logs". All TRACE/DEBUG events for hooks and file operations are now strictly conditional and only appear if the physical action is actually performed.
- **Help Interface:** Refactored the `Show-Help` command with strict column alignment, exit code definitions, and comprehensive documentation of bilingual flags (-v/--verbose, -y/--yes).
- **Hardened Argument Parsing:** Updated the main router to use robust array sub-expressions (`@(...)`), preventing null-indexing errors when no arguments are provided.

### Fixed
- **Greedy Regex Bug:** Resolved a flaw in the JSON extraction logic that misidentified nested JSON colons as message prefixes.
- **Variable Delimiter Bug:** Fixed a PowerShell parser error in the logging system by implementing explicit variable delimiters (`${prefix}:`).
- **Telemetry Leakage:** Purged "Dummy Data" from RAW logs; empty variables or irrelevant placeholders (like empty input paths during bootstrap) are now correctly suppressed.

## [e12b6a0] - 2026-05-28
### Fixed
- **Dependency String Hardening:** Updated `Check-RomsDependencies` in `lib/core.ps1` to strip version constraints (e.g., everything after the colon) from package names before verifying metadata existence. This ensures the engine can correctly validate dependencies that were resolved and passed by the high-level manager.

## [c9ac5b3] - 2026-05-27
### Added
- **Environment Orchestration:** Implemented the `environment_variables` manifest field. The engine now supports persistent system-level configuration (User/Machine scope) using native .NET.
- **Artifact Tracking:** Introduced `env:` prefix for environment variable artifacts in metadata, allowing for surgical cleanup during uninstallation.
- **Unified Logging:** Enabled per-package logging for the `uninstall` command to improve auditability of system cleanup actions.

## [abe4087] - 2026-05-26
### Added
- **Success Handshake:** Added "Modular Engine Handshake active" log to provide empirical proof of successful modular initialization.

## [7ea292e] - 2026-05-26
### Changed
- **Bootstrap Modularization:** Relocated the engine's self-registration logic to a dedicated `lib/bootstrap.ps1` module.
- **Pure Environment Module:** Restored `lib/environment.ps1` to a pure state focused exclusively on system PATH and shim management.
- **Router Compliance:** Updated the engine entry point to follow the industrial-strength modular loading sequence.

## [7fa87fc] - 2026-05-25
### Fixed
- **Positional Data Integrity:** Forced `[array]` type casting on positional arguments to resolve a character-indexing bug (the 'o' input error).
- **Transactional Success Handshake:** Added explicit `exit 0` to all success paths and honored the `AutoConfirm` flag in UI advice blocks.

## [a64a155] - 2026-05-25
### Added
- **Bootstrap Command:** Implemented first-class support for the `bootstrap` command to handle self-registration and shim creation during manager-led recovery.

### Changed
- **Router Compliance:** Refactored the main entry point to strictly follow the Global Flag Pattern ($args -contains) and index-based positional parsing as per Design Standards.
- **Industrial Strength CLI:** Purged legacy "PowerShell-style" switches in favor of standard hyphenated flags.

## [21798d1] - 2026-05-24
### Added
- **Modular Hook System:** Introduced `lib/hooks.ps1` for centralized, manifest-driven hook management.
- **Full Lifecycle Support:** Added support for `pre-install`, `post-install`, `pre-uninstall`, and `post-uninstall` events.
- **Path Integrity:** Implemented "Slash-Agnostic" pathing and auto-directory provisioning to support hooks located in subdirectories.
- **Staged Persistence:** Implemented temporary staging for post-uninstall scripts to ensure availability after application directory removal.

## [5a8ea2d] - 2026-05-23
### Fixed
- **Lifecycle Hook Hardening:** Implemented support for manifest-defined `hooks` and enforced success verification via `$LASTEXITCODE` to prevent silent installation failures.
- **Hook Extraction:** Hardened the ZIP extractor to automatically pull hook scripts even if missing from the `files` array.
- **Rollback Hygiene:** Fixed a metadata cleanup bug by standardizing on the package `name` for all registry operations during rollback.

## [9892313] - 2026-05-23
### Added
- **Trinity v1.1.0 Logic Sync**:
  - Hardened metadata registration to persist verified SHA256 hashes and architecture/author fields.
  - Enforced the "Name-as-Folder" installation standard.

---

## [b0b2dd2] - 2026-05-20
### Fixed
- **Current Directory Pollution:** Enforced absolute, anchored path resolution for all installations to prevent apps from installing in the user's working directory.
- **Broken Shims:** Forced absolute path resolution for all entry points, ensuring shims work correctly regardless of the caller's location.

### Changed
- **Manifest Standardization (Relocatable Apps):** Purged `installDir` from the engine logic. Application folders are now strictly derived from the package `name`.
- **Metadata Registry Cleanup:** Removed persistence of the deprecated `installDir` property in the metadata database; the uninstaller now resolves paths dynamically based on the package name.

---

## [f0676c1] - 2026-05-18
### Added
- **Flexible Dependency Validation:** Hardened the engine-side dependency checker to support both array and object-based manifest formats for the Atomic AVC model.
- **Transaction Depth:** Improved transaction reliability for multi-package orchestrated installs.

---

## [8b6062a] - 2026-05-16
### Added
- **Hardened Path Resolution:** Implemented mandatory absolute path resolution for executables and directories to ensure reliability during UAC elevation and manager hand-off.
- **Manager-Led Orchestration:** Added `-noShim` switch to allow the manager (`roms`) to control environment orchestration.

### Changed
- **Metadata Persistence:** Enhanced metadata records to include `installDir` and `executable` for reliable standalone uninstallation.

---

## [f16f31d] - 2026-05-14
### Added
- **Initial Release:** Core `rmspkg` engine with transactional installation and atomic rollback.
- **Industrial Strength (.NET Rule):** Standardized on native .NET `ZipFile` and `SHA256` primitives for zero-dependency portability.
- **Lifecycle Hooks:** Support for `rms_install.ps1` and `rms_uninstall.ps1` post-extraction scripts.
- **Metadata Registry:** Hidden registry in `C:\roms\.metadata` for artifact tracking.

# Changelog - rmspkg (Package Installer)

All notable changes to the `rmspkg` standalone engine will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

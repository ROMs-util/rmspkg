# make_fixtures.py - Builds attack and happy-path .rms packages for the
# pre-merge E2E security suite (plan: .gemini/plans/security_e2e_validation_v1.md).
#
# WHY PYTHON: per the No-Corrupt-Strings mandate, PowerShell/ZIP fixtures are
# generated from Python so JSON quoting and ZIP entry names stay byte-exact.
# Each manifest encodes exactly one audit finding's attack shape; the .rms
# files are ZIPs containing roms_package.json plus the referenced payloads.
# Attack ZIPs embed the traversal entry names verbatim INSIDE the archive so
# the extractor is forced to evaluate them (installer.ps1 only extracts
# entries that exist in the ZIP - an absent entry would silently skip the guard).
#
# Usage: python make_fixtures.py <output-dir>

import json
import os
import sys
import zipfile


def write_rms(path: str, manifest: dict, payloads: dict) -> None:
    """Write a .rms (ZIP) with roms_package.json at root plus payload files.

    payload keys are ZIP entry names exactly as they appear in files[]/hooks,
    so traversal fixtures (..\\..) are embedded verbatim to test extraction
    containment, not just manifest parsing.

    WHY verbatim entry names: the engine's extractor compares manifest paths
    after normalizing '/'->'\\' (installer.ps1:84), so a manifest with
    backslash traversal only reaches Get-SafeRelativePath if the ZIP entry is
    stored with LITERAL backslashes (the realistic shape for Windows-authored
    archives). Python's ZipInfo constructor rewrites '\\' to '/' on Windows,
    so we override .filename AFTER construction to store the raw name.
    """
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("roms_package.json", json.dumps(manifest, indent=2))
        for name, content in payloads.items():
            zi = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.filename = name  # restore literal separators post-sanitization
            zf.writestr(zi, content)


HELLO_SCRIPT = "@echo off\r\necho HELLO-E2E-OK\r\n"
SENTINEL_PS1 = "Write-Output 'ATTACK-PAYLOAD-EXECUTED'\r\n"

FIXTURES = {
    # Baseline happy path for lifecycle round trip.
    "hello.rms": (
        {
            "name": "sec-e2e-hello",
            "version": "1.0.0",
            "commandName": "sec-e2e-hello",
            "executable": "hello.bat",
            "files": ["hello.bat"],
        },
        {"hello.bat": HELLO_SCRIPT},
    ),
    # C2: manifest name is a traversal sequence -> Get-SafeName must reject
    # before appDir or metadata path is ever constructed. (The E2E runner also
    # watches for a log-path escape: rmspkg.ps1 sets $script:logFile from the
    # unvalidated name before the installer guards it.)
    "evil_name.rms": (
        {
            "name": "..\\sec-e2e-esc",
            "version": "1.0.0",
            "commandName": "sec-e2e-esc",
            "executable": "hello.bat",
            "files": ["hello.bat"],
        },
        {"hello.bat": HELLO_SCRIPT},
    ),
    # H3/M2: files[] entry traverses out of appDir during extraction. The
    # traversal entry must physically exist in the ZIP to reach the guard.
    "evil_file.rms": (
        {
            "name": "sec-e2e-h3",
            "version": "1.0.0",
            "commandName": "sec-e2e-h3",
            "executable": "hello.bat",
            "files": ["hello.bat", "..\\..\\..\\..\\Windows\\sec-e2e-h3-file.txt"],
        },
        {
            "hello.bat": HELLO_SCRIPT,
            "..\\..\\..\\..\\Windows\\sec-e2e-h3-file.txt": HELLO_SCRIPT,
        },
    ),
    # C1/H1: manifest hooks.preInstall points outside appDir. Must be rejected
    # by Get-SafeRelativePath/Assert-PathWithinRoot before pwsh is ever invoked.
    "evil_hook.rms": (
        {
            "name": "sec-e2e-h1",
            "version": "1.0.0",
            "commandName": "sec-e2e-h1",
            "executable": "hello.bat",
            "files": ["hello.bat"],
            "hooks": {"preInstall": "..\\..\\..\\..\\Windows\\sec-e2e-h1-hook.ps1"},
        },
        {
            "hello.bat": HELLO_SCRIPT,
            "..\\..\\..\\..\\Windows\\sec-e2e-h1-hook.ps1": SENTINEL_PS1,
        },
    ),
    # H2: executable string carries a CMD metacharacter injection. The shim (or
    # the path resolver) must neutralize it; executing must NOT run the
    # injected command (sentinel file C:\\sec-e2e-h2-pwned.txt never appears).
    "evil_shim.rms": (
        {
            "name": "sec-e2e-h2",
            "version": "1.0.0",
            "commandName": "sec-e2e-h2",
            "executable": "hello.bat & echo PWNED > C:\\sec-e2e-h2-pwned.txt",
            "files": ["hello.bat"],
        },
        {"hello.bat": HELLO_SCRIPT},
    ),
    # L1: dependency identifier is a traversal token -> stripped lookup must
    # reject through Get-SafeName before any metadata path is tested.
    "evil_dep.rms": (
        {
            "name": "sec-e2e-l1",
            "version": "1.0.0",
            "commandName": "sec-e2e-l1",
            "executable": "hello.bat",
            "files": ["hello.bat"],
            "dependencies": {"packages": ["..\\..\\evil:^1.0.0"]},
        },
        {"hello.bat": HELLO_SCRIPT},
    ),
    # Characterization of the known gap: environment_variables calls a function
    # that no longer exists (installer.ps1:144). Expected to FAIL install until
    # the gap is closed; this fixture documents the behavior, not a guard.
    "envvar.rms": (
        {
            "name": "sec-e2e-env",
            "version": "1.0.0",
            "commandName": "sec-e2e-env",
            "executable": "hello.bat",
            "files": ["hello.bat"],
            "environment_variables": {"FOO": "BAR"},
        },
        {"hello.bat": HELLO_SCRIPT},
    ),
}


def main() -> int:
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out_dir, exist_ok=True)
    for fname, (manifest, payloads) in FIXTURES.items():
        write_rms(os.path.join(out_dir, fname), manifest, payloads)
        print(f"built {fname}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

# package_installer Test Suite

## Quick Start

```powershell
# Run all four suites in order:
pwsh -File tests/Test-Guards.ps1      # Phase A: unit-level guard contracts
pwsh -File tests/Run-E2E.ps1          # Phase B/C/D: E2E security + lifecycle
pwsh -File tests/Run-Lab.ps1          # Lab: package_testnet scenarios (hooks, rollback, env vars)
pwsh -File tests/Negative-Cases.ps1   # Error-path negative tests
```

## Suite Architecture

| File | Phase | Purpose | Baseline |
|------|-------|---------|----------|
| `Test-Guards.ps1` | A | Unit tests for `lib/safety.ps1` guards and `lib/environment.ps1` CMD escaping | 30/30 |
| `Run-E2E.ps1` | B/C/D | E2E security attacks, lifecycle round-trip, verbosity regression | 74/74 |
| `Run-Lab.ps1` | Lab | Engine-level tests using `package_testnet` .rms files: hooks, rollback, env vars, metadata tracking | 40/40 |
| `Negative-Cases.ps1` | -- | Error-path coverage for pre-rc fixes (P1b, P4, P6, P8) | 6/6 |

## Fixture Builder

`make_fixtures.py` generates `.rms` ZIP packages from Python for byte-exact control over ZIP entry names. Each fixture encodes one attack shape or happy-path scenario.

**Why Python:** per the No-Corrupt-Strings mandate, PowerShell/ZIP fixtures are generated from Python so JSON quoting and ZIP entry names stay byte-exact.

### Fixtures

| File | Test | Attack Shape |
|------|------|-------------|
| `hello.rms` | C1 lifecycle | Happy path: install, shim exec, uninstall |
| `evil_name.rms` | B1 | Manifest name is `..\ traversal` -- `Get-SafeName` rejects |
| `evil_file.rms` | B2 | `files[]` traverses out of appDir -- extraction guard rejects |
| `evil_hook.rms` | B3 | `hooks.preInstall` points outside appDir -- path guard rejects |
| `evil_shim.rms` | B4 | Executable string has CMD metachar injection -- shim escaping neutralizes |
| `evil_dep.rms` | B5 | Dependency identifier is traversal -- `Get-SafeName` rejects |
| `envvar.rms` | B6 | Sets `environment_variables` -- tests env orchestration + uninstall purge |

## Phase Details

### Phase A: Test-Guards.ps1

Unit-level guard contracts. Tests `Get-SafeName`, `Assert-PathWithinRoot`, `Get-SafeRelativePath`, and `Get-CmdEscapedPath` in isolation. Must pass before E2E.

### Phase B: Attack Fixtures

Each malicious `.rms` is installed and asserted to:
- Exit with code 1
- Emit exactly one `[ERROR]` containment line
- Leave zero payload files outside the sandbox

### Phase C: Lifecycle Round Trip

Happy-path install -> shim exec -> uninstall leaves no residue. Includes nested hook paths (C2) and escaping-artifact skip behavior (C3).

### Phase D: Verbosity Regression

Re-runs the H3 traversal attack at `-v`, `-vv`, `-vvv` to verify the single-error-line contract holds at every verbosity level.

### Negative Cases

Error-path tests that the happy-path E2E does not reach:

| Test | What It Does |
|------|-------------|
| P1b | Pre-sets a conflicting User env var, installs, verifies WARN emitted |
| P4 | Corrupts metadata name to traversal, calls uninstall, verifies error logged |
| P6 | Deletes `C:\roms\logs` before install, verifies directory auto-created |
| P8 | Calls `Assert-PathWithinRoot` with mismatched casing, verifies acceptance |

## Adding New Tests

1. **Guard tests** go in `Test-Guards.ps1` -- keep them isolated (no filesystem side effects).
2. **E2E attack fixtures** go in `make_fixtures.py` -- add a new entry to `FIXTURES` dict.
3. **Lifecycle scenarios** go in `Run-E2E.ps1` Phase C.
4. **Error-path tests** go in `Negative-Cases.ps1`.

All test files follow the `Report` assertion pattern and clean up every artifact they create.

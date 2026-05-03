# ROMs Installer

A generic, reusable installer for any PowerShell script, tool, or application on Windows. Driven entirely by `roms_package.json` — no hardcoded values inside the installer itself.

---

## Purpose

One installer that works across all projects. Instead of writing a custom install script for every tool you build, reuse this installer by providing a `roms_package.json` config file per project. The installer reads the config, validates dependencies, deploys files, and registers the command in User PATH.

---

## Files

| File | Role |
|---|---|
| `install.ps1` | Core installer - reads config, validates dependencies, deploys files, registers PATH |
| `run.bat` | Launcher - bypasses PowerShell execution policy and runs `install.ps1` |
| `roms_package.json.example` | Config template - copy and fill in for your project |

---

## How to Add This Installer to Any Project

### Step 1 - Copy installer files into your project root

Copy these three files into your project folder:

```
your-project/
    install.ps1
    run.bat
    roms_package.json.example
    ... your project files ...
```

### Step 2 - Create your config file

Copy the example and rename it:

```cmd
copy roms_package.json.example roms_package.json
```

### Step 3 - Fill in roms_package.json

Open `roms_package.json` and replace all placeholder values:

```json
{
    "installDir": "C:\\roms\\your-project-name",
    "commandName": "your-command",
    "files": [
        "your-main-script.ps1",
        "run.bat"
    ],
    "dependencies": {
        "system": {
            "os": "Windows 10 / 11",
            "powershell": "5.1",
            "privileges": "Administrator"
        },
        "tools": {
            "git": "optional",
            "python": "required"
        },
        "scripts": {
            "your-main-script.ps1": "required"
        }
    },
    "metadata": {
        "name": "your-project-name",
        "version": "1.0.0",
        "description": "what this project does",
        "author": "your-name"
    }
}
```

**Key fields to always fill in:**

| Field | What to put |
|---|---|
| `installDir` | Where files will be copied on the target machine |
| `commandName` | The command users will type in terminal |
| `files` | List of files that need to be deployed |
| `metadata.name` | Your project name |
| `metadata.version` | Current version |

### Step 4 - Test locally

Run the installer:

```cmd
run.bat
```

Open a new terminal and verify the command works:

```cmd
your-command
```

### Step 5 - Ship it

Commit these files to your repo:

```
install.ps1
run.bat
roms_package.json
roms_package.json.example
```

Anyone cloning the repo runs `run.bat` to install.

---

## How It Works Internally

```
run.bat
  -> bypasses PowerShell execution policy
  -> launches install.ps1

install.ps1
  -> reads roms_package.json
  -> validates required fields
  -> checks PowerShell version
  -> checks tool dependencies (required: exit | optional: warn)
  -> checks script dependencies (required: exit | optional: warn)
  -> creates installDir if not exists
  -> copies all files listed in "files"
  -> adds installDir to User PATH
  -> prints success
```

---

## Dependency Types

### System dependencies
Checked automatically by the installer:

```json
"system": {
    "os": "Windows 10 / 11",       <- informational only
    "powershell": "5.1",            <- minimum version checked
    "privileges": "Administrator"   <- informational only
}
```

### Tool dependencies
External tools that must be installed on the machine:

```json
"tools": {
    "git": "required",     <- installer exits if git not found
    "python": "optional"   <- installer warns but continues
}
```

### Script dependencies
Files that must exist in the project folder before installing:

```json
"scripts": {
    "main.ps1": "required",    <- installer exits if not found
    "helper.ps1": "optional"   <- installer warns but continues
}
```

---

## Uninstalling

**Option 1 - Automatic (recommended):**

Run from the project source folder:
```cmd
run.bat -uninstall
```

This will:
- Ask for confirmation before proceeding
- Delete the package install folder only — parent folder untouched
- Remove install directory from User PATH

Open a new terminal after uninstall to apply PATH changes.

**Option 2 - Manual:**

**1. Delete installed files:**
```cmd
rmdir /S /Q "C:\roms\your-project-name"
```

**2. Remove from User PATH:**
```powershell
$path = [Environment]::GetEnvironmentVariable("PATH", "User")
$newPath = ($path -split ";" | Where-Object { $_ -ne "C:\roms\your-project-name" }) -join ";"
[Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
```

**3. Open a new terminal** - command will no longer be recognized.

---

## Limitations

- Install directory is hardcoded in `roms_package.json` - no interactive path selection yet
- Version checking for tools not yet implemented
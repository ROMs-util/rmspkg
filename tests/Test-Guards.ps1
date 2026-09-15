# Test-Guards.ps1 - Phase A of the pre-merge security E2E plan
# (plan: .gemini/plans/security_e2e_validation_v1.md)
#
# Unit-level verification of the containment guards in lib/safety.ps1 and the
# CMD escaping in lib/environment.ps1. No package is installed here: each
# rejection case must prove the Log-Only Error Abort contract -
#   exactly ONE [ERROR] line via Write-Log, then a message-less
#   [System.Security.SecurityException]("containment") throw, and nothing else.
#
# Expectations below are empirical: 'f:stream' hits the drive-letter branch
# (shadowing the ADS branch) and is asserted as it actually behaves, per the
# physical-truth standard. Since fix#63 every separator-rooted form (single or
# double backslash / slash) is rejected by the normalized UNC probe.

$ErrorActionPreference = "Stop"

# Stub Write-Log BEFORE dot-sourcing the guards so rejections are captured
# in-process instead of touching the real log pipeline.
$script:LogLines = @()
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Source = "Engine"
    )
    $script:LogLines += [PSCustomObject]@{ Level = $Level; Message = $Message }
}

. (Join-Path $PSScriptRoot "..\lib\safety.ps1")
. (Join-Path $PSScriptRoot "..\lib\environment.ps1")

$script:Pass = 0
$script:Fail = 0

function Report {
    param([bool]$Ok, [string]$Name, [string]$Detail)
    if ($Ok) {
        $script:Pass++
        Write-Host "[PASS] $Name"
    } else {
        $script:Fail++
        Write-Host "[FAIL] $Name -- $Detail" -ForegroundColor Red
    }
}

# Asserts the full rejection contract: SecurityException("containment") and
# exactly one ERROR line whose text contains $ExpectError.
function Assert-Rejection {
    param([string]$Name, [scriptblock]$Action, [string]$ExpectError)
    $script:LogLines = @()
    $thrown = $null
    try { & $Action | Out-Null } catch { $thrown = $_.Exception }
    $errors = @($script:LogLines | Where-Object { $_.Level -eq "ERROR" })
    if ($null -eq $thrown) {
        Report $false $Name "no exception thrown"
    } elseif ($thrown -isnot [System.Security.SecurityException] -or $thrown.Message -ne "containment") {
        Report $false $Name "wrong exception: $($thrown.GetType().Name) '$($thrown.Message)'"
    } elseif ($errors.Count -ne 1) {
        Report $false $Name "expected exactly 1 ERROR line, got $($errors.Count)"
    } elseif ($errors[0].Message -notlike "*$ExpectError*") {
        Report $false $Name "ERROR text '$($errors[0].Message)' missing '$ExpectError'"
    } else {
        Report $true $Name ""
    }
}

function Assert-Acceptance {
    param([string]$Name, [scriptblock]$Action, $ExpectedResult = $null)
    $script:LogLines = @()
    $result = $null
    $thrown = $null
    try { $result = & $Action } catch { $thrown = $_.Exception }
    $errors = @($script:LogLines | Where-Object { $_.Level -eq "ERROR" })
    if ($null -ne $thrown) {
        Report $false $Name "threw: $($thrown.Message)"
    } elseif ($errors.Count -ne 0) {
        Report $false $Name "unexpected ERROR log: $($errors[0].Message)"
    } elseif ($null -ne $ExpectedResult -and $result -ne $ExpectedResult) {
        Report $false $Name "got '$result', expected '$ExpectedResult'"
    } else {
        Report $true $Name ""
    }
}

Write-Host "----- Get-SafeName -----"
# Package name is a single identifier: separators, traversal, dots-first and
# drive qualifiers must all be rejected.
Assert-Rejection "name: traversal '..\sec-e2e-esc'" { Get-SafeName "..\sec-e2e-esc" } "Invalid name"
Assert-Rejection "name: leading dot '.hidden'"      { Get-SafeName ".hidden" }      "Invalid name"
Assert-Rejection "name: backslash 'a\b'"            { Get-SafeName "a\b" }          "Invalid name"
Assert-Rejection "name: forward slash 'a/b'"        { Get-SafeName "a/b" }          "Invalid name"
Assert-Rejection "name: drive 'C:foo'"              { Get-SafeName "C:foo" }        "Invalid name"
# Empty string is blocked one layer earlier, by the Mandatory parameter binding
# (ParameterBindingValidationException), never reaching the allowlist. Assert
# that rejection still happens.
$script:LogLines = @()
$emptyThrew = $false
try { Get-SafeName "" | Out-Null } catch { $emptyThrew = $true }
Report $emptyThrew "name: empty string (blocked at parameter binding)" "no exception for empty name"
Assert-Rejection "name: UNC '//srv/share'"          { Get-SafeName "//srv/share" }  "Invalid name"
Assert-Acceptance "name: plain 'sec-e2e-hello'"     { Get-SafeName "sec-e2e-hello" } "sec-e2e-hello"
Assert-Acceptance "name: dots/hyphen/underscore 'a.b-c_1'" { Get-SafeName "a.b-c_1" } "a.b-c_1"

Write-Host "----- Assert-PathWithinRoot -----"
Assert-Acceptance    "root: descendant 'C:\roms\pkg'"       { Assert-PathWithinRoot -Path "C:\roms\pkg" -Root "C:\roms" } "C:\roms\pkg"
Assert-Acceptance    "root: the root itself"                { Assert-PathWithinRoot -Path "C:\roms" -Root "C:\roms" }     "C:\roms"
Assert-Acceptance    "root: trailing-slash root accepted"   { Assert-PathWithinRoot -Path "C:\roms\sub" -Root "C:\roms\" } "C:\roms\sub"
Assert-Rejection     "root: sibling-prefix trick 'C:\roms2'" { Assert-PathWithinRoot -Path "C:\roms2\evil" -Root "C:\roms" } "escapes root"
Assert-Rejection     "root: unrelated drive path"            { Assert-PathWithinRoot -Path "C:\other\x" -Root "C:\roms" }   "escapes root"
Assert-Rejection     "root: traversal escape '..\x'"         { Assert-PathWithinRoot -Path "C:\roms\..\windows" -Root "C:\roms" } "escapes root"

Write-Host "----- Get-SafeRelativePath -----"
$R = "C:\roms"
Assert-Acceptance    "rel: nested 'sub/ok.txt'"              { Get-SafeRelativePath -Relative "sub/ok.txt" -Root $R } "C:\roms\sub\ok.txt"
Assert-Acceptance    "rel: bare file 'hello.bat'"            { Get-SafeRelativePath -Relative "hello.bat" -Root $R }  "C:\roms\hello.bat"
Assert-Rejection     "rel: leading '..'"                     { Get-SafeRelativePath -Relative ".." -Root $R }                     "traversal segment"
Assert-Rejection     "rel: embedded 'a/../../b'"             { Get-SafeRelativePath -Relative "a/../../b" -Root $R }              "traversal segment"
Assert-Rejection     "rel: four-level up (fixture shape)"    { Get-SafeRelativePath -Relative "..\..\..\..\Windows\x.txt" -Root $R } "traversal segment"
Assert-Rejection     "rel: forward-slash UNC '//srv/share'"  { Get-SafeRelativePath -Relative "//srv/share" -Root $R }            "UNC prefix"
Assert-Rejection     "rel: drive-rooted 'C:x'"               { Get-SafeRelativePath -Relative "C:x" -Root $R }                    "drive-letter segment"
Assert-Rejection     "rel: ADS-looking 'f:stream' hits drive-letter branch (shadowed ADS check)" `
                     { Get-SafeRelativePath -Relative "f:stream" -Root $R } "drive-letter segment"
# fix#63: separator normalization makes ALL separator-rooted forms reject
# deterministically (before the join), including the single-leading-separator
# forms that previously relied on Join-Path swallowing them into Root.
$twoBs = [string][char]92 + [char]92 + 'server\share'
$oneBs = [string][char]92 + 'server\share'
Assert-Rejection     "rel: double-backslash UNC (2 leading \) rejected" { Get-SafeRelativePath -Relative $twoBs -Root $R } "UNC prefix"
Assert-Rejection     "rel: single-leading-backslash '\server\share' rejected" `
                     { Get-SafeRelativePath -Relative $oneBs -Root $R } "UNC prefix"
Assert-Rejection     "rel: single-leading-slash '/server/share' rejected" `
                     { Get-SafeRelativePath -Relative "/server/share" -Root $R } "UNC prefix"

Write-Host "----- Get-CmdEscapedPath (H2) -----"
# Caret must be doubled FIRST, then each of & | < > is caret-escaped. Wrong
# order would let the injected carets themselves escape the following char.
Assert-Acceptance "esc: '& | < >' all caret-escaped"     { Get-CmdEscapedPath "a&b|c<d>e" } "a^&b^|c^<d^>e"
Assert-Acceptance "esc: caret doubled before metachars"  { Get-CmdEscapedPath "^&" }        "^^^&"
Assert-Acceptance "esc: injection sample"                { Get-CmdEscapedPath "hello.bat & echo PWNED > C:\x.txt" } "hello.bat ^& echo PWNED ^> C:\x.txt"
Assert-Acceptance "esc: plain path untouched"            { Get-CmdEscapedPath "C:\roms\bin\tool.bat" } "C:\roms\bin\tool.bat"

Write-Host "-----"
Write-Host "Test-Guards: $script:Pass passed, $script:Fail failed"
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }

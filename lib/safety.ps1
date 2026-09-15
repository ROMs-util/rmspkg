# ---------------------------------------------
# PATH & NAME SAFETY (Containment Guards)
# Central trust-boundary validators. Every value that originates from a
# package manifest (name, file list, hook path, artifact) must pass through
# these functions before it is joined to a filesystem root. This prevents a
# malicious package from escaping the sandboxed ecosystem root ($global:ROMs_ROOT)
# via ".." traversal, absolute paths, or drive-letter tricks.
# HOW IT WORKS:
# 1. Get-SafeName rejects anything that is not a plain identifier token.
# 2. Assert-PathWithinRoot canonicalizes a candidate path under a root and
#    guarantees the result is still inside that root.
# 3. Get-SafeRelativePath validates a manifest-relative file/hook path and
#    resolves it under a trusted root, rejecting traversal/absolute escapes.
# All use native .NET ([System.IO.Path]) directly for version-proof behavior
# (the .NET Rule). Per DESIGN_STANDARDS.md §10 "Log-Only Error Abort", every
# rejection emits a tagged [ERROR] entry via Write-Log (the single log
# pipeline) and then throws a message-less sentinel to abort without a
# duplicate message.
# ---------------------------------------------

function Get-SafeName {
    # Validates a package/command name against a strict allowlist. A package
    # "name" is a single identifier, never a path, so it must contain only
    # letters, digits, dot, underscore, or hyphen, and must not begin with a
    # separator. This blocks "..", "/", "\", drive letters ("C:"), and UNC.
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    $allowlist = '^[A-Za-z0-9][A-Za-z0-9._-]*$'
    if ($Name -notmatch $allowlist) {
        Write-Log "Invalid name '$Name': must match $allowlist (no path separators or '..')" "ERROR"
        throw [System.Security.SecurityException]::new("containment")
    }
    return $Name
}

function Assert-PathWithinRoot {
    # Returns the full path of Path only if it is equal to Root or a descendant
    # of Root. Root is resolved to an absolute path first so the containment
    # comparison is stable. On escape, throws a terminating error to abort the
    # operation before any file writes occur.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)

    if ($resolvedPath -eq $resolvedRoot) {
        return $resolvedPath
    }

    if ($resolvedPath.StartsWith($resolvedRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath
    }

    Write-Log "Path '$resolvedPath' escapes root '$resolvedRoot'" "ERROR"
    throw [System.Security.SecurityException]::new("containment")
}

function Get-SafeRelativePath {
    # Validates a relative path taken from a package manifest (files[] entry or
    # hook path) and resolves it under Root, guaranteeing the result stays inside
    # Root. A valid relative path must not traverse upward (".."), must not be a
    # rooted/drive-qualified path (":"), and must not carry an NTFS Alternate
    # Data Stream ("file:stream"). On violation it throws before any join/write.
    # Returns the full resolved path inside Root.
    param(
        [Parameter(Mandatory = $true)][string]$Relative,
        [Parameter(Mandatory = $true)][string]$Root
    )

    # UNC-prefix check. NOTE: the leading-'\\' (double-backslash) branch is
    # effectively dead for the engine's call sites. All callers pass a
    # manifest-relative path fetched from Get-RomsHookPath or a files[] entry,
    # and those are single-segment/forward-slash values; a raw two-backslash
    # string ("\\server\share") is a legal Windows path character sequence, so
    # PowerShell's Join-Path treats it as a relative segment list and the value
    # is swallowed into Root (it resolves to <Root>\server\share) rather than
    # matching this StartsWith('\\') test. The '//' (forward-slash) form IS
    # caught here. This is a defense-in-depth inconsistency, NOT a live escape:
    # the swallowed path is still fully contained inside Root (and any ".."
    # segments are still rejected below), so no write can leave Root. See
    # TODO.md ("Double-backslash UNC prefix not rejected") for a recommended,
    # safe hardening that normalizes separator form before this check.
    if ($Relative.StartsWith('\\') -or $Relative.StartsWith('//')) {
        Write-Log "Relative path '$Relative' contains a UNC prefix" "ERROR"
        throw [System.Security.SecurityException]::new("containment")
    }
    if ($Relative -match '^[A-Za-z]:') {
        Write-Log "Relative path '$Relative' contains a drive-letter segment" "ERROR"
        throw [System.Security.SecurityException]::new("containment")
    }

    foreach ($seg in ($Relative -split '[\\/]')) {
        if ($seg -eq '..') {
            Write-Log "Relative path '$Relative' contains a '..' traversal segment" "ERROR"
            throw [System.Security.SecurityException]::new("containment")
        }
        if ($seg -match ':') {
            Write-Log "Relative path '$Relative' contains an Alternate Data Stream separator" "ERROR"
            throw [System.Security.SecurityException]::new("containment")
        }
    }

    return Assert-PathWithinRoot -Path (Join-Path $Root $Relative) -Root $Root
}
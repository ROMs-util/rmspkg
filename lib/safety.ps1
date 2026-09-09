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
# Both use native .NET ([System.IO.Path]) directly for version-proof behavior.
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
        throw "Invalid name '$Name': must match $allowlist (no path separators or '..')"
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

    throw "Path '$resolvedPath' escapes root '$resolvedRoot'"
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

    if ($Relative.StartsWith('\\') -or $Relative.StartsWith('//')) {
        throw "Relative path '$Relative' contains a UNC prefix"
    }
    if ($Relative -match '^[A-Za-z]:') {
        throw "Relative path '$Relative' contains a drive-letter segment"
    }

    foreach ($seg in ($Relative -split '[\\/]')) {
        if ($seg -eq '..') {
            throw "Relative path '$Relative' contains a '..' traversal segment"
        }
        if ($seg -match ':') {
            throw "Relative path '$Relative' contains an Alternate Data Stream separator"
        }
    }

    return Assert-PathWithinRoot -Path (Join-Path $Root $Relative) -Root $Root
}
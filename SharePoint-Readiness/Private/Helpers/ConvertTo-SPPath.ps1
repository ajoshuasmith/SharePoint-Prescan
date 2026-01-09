function ConvertTo-SPPath {
    <#
    .SYNOPSIS
        Converts a local file path to a SharePoint-compatible path.

    .DESCRIPTION
        Takes a local Windows file path and converts it to the format
        that would be used in SharePoint, replacing invalid characters
        and adjusting path separators.

    .PARAMETER LocalPath
        The local file path to convert.

    .PARAMETER SourceRoot
        The root path being scanned (to calculate relative path).

    .PARAMETER ReplaceInvalidChars
        If true, replaces invalid characters with safe alternatives.

    .OUTPUTS
        PSCustomObject with original and converted paths.

    .EXAMPLE
        ConvertTo-SPPath -LocalPath "C:\Data\Reports\Q4: Summary.docx" -SourceRoot "C:\Data"
        # Returns object with SharePoint-compatible path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalPath,

        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter()]
        [switch]$ReplaceInvalidChars
    )

    # Calculate relative path
    $sourceRoot = $SourceRoot.TrimEnd('\', '/')
    $relativePath = $LocalPath

    if ($LocalPath.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $LocalPath.Substring($sourceRoot.Length).TrimStart('\', '/')
    }

    # Convert backslashes to forward slashes
    $spPath = $relativePath.Replace('\', '/')

    # Track if any changes were made
    $changes = @()
    $originalPath = $spPath

    if ($ReplaceInvalidChars) {
        # Invalid characters in SharePoint: " * : < > ? / \ |
        # Note: \ already converted to /, / is valid in paths

        $replacements = @{
            '"' = "'"
            '*' = '_'
            ':' = '-'
            '<' = '('
            '>' = ')'
            '?' = ''
            '|' = '-'
        }

        foreach ($char in $replacements.Keys) {
            if ($spPath.Contains($char)) {
                $changes += "Replaced '$char' with '$($replacements[$char])'"
                $spPath = $spPath.Replace($char, $replacements[$char])
            }
        }

        # Clean up multiple dashes/underscores
        if ($spPath -match '[-_]{2,}') {
            $spPath = $spPath -replace '[-_]{2,}', '-'
            $changes += "Cleaned up multiple dashes/underscores"
        }

        # Remove leading/trailing spaces from each path segment
        $segments = $spPath.Split('/')
        $cleanedSegments = $segments | ForEach-Object { $_.Trim() }
        $newPath = $cleanedSegments -join '/'
        if ($newPath -ne $spPath) {
            $changes += "Trimmed spaces from path segments"
            $spPath = $newPath
        }
    }

    [PSCustomObject]@{
        LocalPath = $LocalPath
        SourceRoot = $SourceRoot
        RelativePath = $relativePath
        SharePointPath = $spPath
        WasModified = $changes.Count -gt 0
        Changes = $changes
    }
}

function Get-RelativePath {
    <#
    .SYNOPSIS
        Gets the relative path from a root to a target path.

    .DESCRIPTION
        Calculates the relative path from a source root to a target path.

    .PARAMETER Path
        The full path.

    .PARAMETER Root
        The root path to calculate relative from.

    .OUTPUTS
        The relative path string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Root
    )

    $root = $Root.TrimEnd('\', '/')
    $path = $Path.TrimEnd('\', '/')

    if ($path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $path.Substring($root.Length).TrimStart('\', '/')
    }

    return $path
}

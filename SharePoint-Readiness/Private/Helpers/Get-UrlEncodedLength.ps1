function Get-UrlEncodedLength {
    <#
    .SYNOPSIS
        Calculates the URL-encoded length of a path.

    .DESCRIPTION
        SharePoint counts URL-encoded characters against the path limit.
        This function calculates what the actual length will be after
        encoding special characters (spaces become %20, etc.).

    .PARAMETER Path
        The path to measure.

    .PARAMETER PreserveSlashes
        If true, forward slashes are not encoded.

    .OUTPUTS
        PSCustomObject with original and encoded lengths.

    .EXAMPLE
        Get-UrlEncodedLength -Path "Documents/My File (2024).docx"
        # Returns object showing original length and encoded length
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path,

        [Parameter()]
        [switch]$PreserveSlashes
    )

    process {
        # Normalize path separators
        $normalizedPath = $Path.Replace('\', '/')

        # URL encode the path
        if ($PreserveSlashes) {
            # Encode each segment separately to preserve slashes
            $segments = $normalizedPath.Split('/')
            $encodedSegments = $segments | ForEach-Object {
                [System.Uri]::EscapeDataString($_)
            }
            $encodedPath = $encodedSegments -join '/'
        }
        else {
            $encodedPath = [System.Uri]::EscapeDataString($normalizedPath)
        }

        # Calculate lengths
        $originalLength = $normalizedPath.Length
        $encodedLength = $encodedPath.Length
        $difference = $encodedLength - $originalLength

        # Identify characters that were encoded
        $specialChars = @()
        $charPattern = '%[0-9A-Fa-f]{2}'
        $matches = [regex]::Matches($encodedPath, $charPattern)
        foreach ($match in $matches) {
            $decoded = [System.Uri]::UnescapeDataString($match.Value)
            if ($specialChars -notcontains $decoded) {
                $specialChars += $decoded
            }
        }

        [PSCustomObject]@{
            OriginalPath = $normalizedPath
            EncodedPath = $encodedPath
            OriginalLength = $originalLength
            EncodedLength = $encodedLength
            LengthDifference = $difference
            EncodedCharacters = $specialChars
            HasSpecialChars = $difference -gt 0
        }
    }
}

function Test-PathContainsEncodableChars {
    <#
    .SYNOPSIS
        Tests if a path contains characters that will be URL-encoded.

    .DESCRIPTION
        Quick check to see if a path contains characters that will
        increase its length when URL-encoded for SharePoint.

    .PARAMETER Path
        The path to test.

    .OUTPUTS
        Boolean indicating if path contains encodable characters.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Characters that get URL-encoded and take extra space
    # Space becomes %20 (1 char -> 3 chars)
    # Most non-alphanumeric chars get encoded
    $encodablePattern = '[\s!#$%&''()+,;=@\[\]^`{}~]'

    return $Path -match $encodablePattern
}

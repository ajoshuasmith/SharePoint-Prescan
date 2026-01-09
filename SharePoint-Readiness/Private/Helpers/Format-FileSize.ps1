function Format-FileSize {
    <#
    .SYNOPSIS
        Formats a file size in bytes to a human-readable string.

    .DESCRIPTION
        Converts bytes to the most appropriate unit (KB, MB, GB, TB)
        with configurable decimal places.

    .PARAMETER Bytes
        The size in bytes to format.

    .PARAMETER DecimalPlaces
        Number of decimal places to show (default: 2).

    .OUTPUTS
        Formatted string like "1.5 GB" or "256 KB".

    .EXAMPLE
        Format-FileSize -Bytes 1073741824
        # Returns: "1.00 GB"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [long]$Bytes,

        [Parameter()]
        [int]$DecimalPlaces = 2
    )

    process {
        $sizes = @(
            @{ Unit = 'TB'; Size = 1TB }
            @{ Unit = 'GB'; Size = 1GB }
            @{ Unit = 'MB'; Size = 1MB }
            @{ Unit = 'KB'; Size = 1KB }
        )

        foreach ($size in $sizes) {
            if ($Bytes -ge $size.Size) {
                $value = $Bytes / $size.Size
                return "{0:N$DecimalPlaces} {1}" -f $value, $size.Unit
            }
        }

        return "$Bytes bytes"
    }
}

function ConvertTo-Bytes {
    <#
    .SYNOPSIS
        Converts a human-readable size string to bytes.

    .DESCRIPTION
        Parses strings like "1.5 GB" or "256 MB" and returns bytes.

    .PARAMETER SizeString
        The size string to parse.

    .OUTPUTS
        Size in bytes as a long integer.

    .EXAMPLE
        ConvertTo-Bytes -SizeString "1.5 GB"
        # Returns: 1610612736
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$SizeString
    )

    process {
        $SizeString = $SizeString.Trim()

        $multipliers = @{
            'TB' = 1TB
            'GB' = 1GB
            'MB' = 1MB
            'KB' = 1KB
            'B'  = 1
            'BYTES' = 1
        }

        foreach ($unit in $multipliers.Keys) {
            if ($SizeString -match "^([\d.]+)\s*$unit$") {
                $value = [double]$Matches[1]
                return [long]($value * $multipliers[$unit])
            }
        }

        # Try parsing as raw bytes
        if ($SizeString -match '^\d+$') {
            return [long]$SizeString
        }

        throw "Could not parse size string: $SizeString"
    }
}

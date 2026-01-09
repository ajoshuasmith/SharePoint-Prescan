function Test-InvalidCharacters {
    <#
    .SYNOPSIS
        Tests if a file or folder name contains characters invalid for SharePoint Online.

    .DESCRIPTION
        Checks the item name for characters that are not allowed in SharePoint Online:
        " * : < > ? / \ |

    .PARAMETER Item
        The file system item to test (FileInfo or DirectoryInfo object).

    .PARAMETER InvalidCharacters
        Array of invalid characters to check for.

    .OUTPUTS
        PSCustomObject with Issue details if problems found, $null otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter()]
        [char[]]$InvalidCharacters = @('"', '*', ':', '<', '>', '?', '/', '\', '|')
    )

    $issues = @()
    $itemName = $Item.Name

    # Find all invalid characters in the name
    $foundInvalidChars = @()
    foreach ($char in $InvalidCharacters) {
        if ($itemName.Contains($char)) {
            $foundInvalidChars += $char
        }
    }

    if ($foundInvalidChars.Count -gt 0) {
        # Create a suggested replacement name
        $suggestedName = $itemName
        foreach ($char in $foundInvalidChars) {
            $replacement = switch ($char) {
                ':' { '-' }
                '"' { "'" }
                '*' { '_' }
                '<' { '(' }
                '>' { ')' }
                '?' { '' }
                '/' { '-' }
                '\' { '-' }
                '|' { '-' }
                default { '_' }
            }
            $suggestedName = $suggestedName.Replace($char, $replacement)
        }

        # Clean up multiple dashes/underscores
        $suggestedName = $suggestedName -replace '[-_]{2,}', '-'
        $suggestedName = $suggestedName.Trim('-', '_', ' ')

        $charDisplay = ($foundInvalidChars | ForEach-Object { "'$_'" }) -join ', '

        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = if ($Item.PSIsContainer) { 'Folder' } else { 'File' }
            Issue = 'InvalidCharacters'
            IssueDescription = "Name contains invalid characters: $charDisplay"
            Severity = 'Critical'
            Category = 'Invalid Characters'
            InvalidChars = $foundInvalidChars
            Suggestion = "Rename to remove invalid characters. Suggested: '$suggestedName'"
            SuggestedName = $suggestedName
        }
    }

    # Check for leading/trailing spaces (problematic but not blocked)
    if ($itemName -ne $itemName.Trim()) {
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = if ($Item.PSIsContainer) { 'Folder' } else { 'File' }
            Issue = 'LeadingTrailingSpaces'
            IssueDescription = 'Name has leading or trailing spaces'
            Severity = 'Warning'
            Category = 'Invalid Characters'
            Suggestion = "Rename to remove leading/trailing spaces. Suggested: '$($itemName.Trim())'"
            SuggestedName = $itemName.Trim()
        }
    }

    # Check for leading/trailing periods (blocked in some scenarios)
    if ($itemName.StartsWith('.') -and $itemName -ne '..' -and $itemName.Length -gt 1) {
        # Hidden files starting with . are okay, but just . or ending with . is not
    }
    if ($itemName.EndsWith('.') -and -not $Item.PSIsContainer) {
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = 'File'
            Issue = 'TrailingPeriod'
            IssueDescription = 'File name ends with a period'
            Severity = 'Warning'
            Category = 'Invalid Characters'
            Suggestion = "Remove trailing period from file name."
            SuggestedName = $itemName.TrimEnd('.')
        }
    }

    return $issues
}

function Test-PathLength {
    <#
    .SYNOPSIS
        Tests if a file path exceeds SharePoint Online path length limits.

    .DESCRIPTION
        Validates the total path length against SharePoint Online's 400 character limit,
        accounting for the destination URL that will be prepended during migration.

    .PARAMETER Item
        The file system item to test (FileInfo or DirectoryInfo object).

    .PARAMETER RelativePath
        The relative path from the scan root.

    .PARAMETER DestinationPathLength
        The character count of the SharePoint destination path.

    .PARAMETER MaxPathLength
        Maximum allowed path length (default: 400).

    .PARAMETER WarningThresholdPercent
        Percentage of max length at which to issue a warning (default: 80).

    .OUTPUTS
        PSCustomObject with Issue details if problems found, $null otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [int]$DestinationPathLength,

        [Parameter()]
        [int]$MaxPathLength = 400,

        [Parameter()]
        [int]$WarningThresholdPercent = 80
    )

    $issues = @()

    # Calculate the full path length in SharePoint
    # RelativePath already excludes the source root, just need to add destination length
    $relativePathLength = $RelativePath.Length
    $totalPathLength = $DestinationPathLength + $relativePathLength

    # Also check URL-encoded length (spaces become %20, etc.)
    $encodedRelativePath = [System.Uri]::EscapeDataString($RelativePath) -replace '%2F', '/'
    $encodedPathLength = $DestinationPathLength + $encodedRelativePath.Length

    # Use the larger of the two (encoded paths are what SharePoint actually uses)
    $effectiveLength = [Math]::Max($totalPathLength, $encodedPathLength)
    $availableChars = $MaxPathLength - $DestinationPathLength

    # Check individual file/folder name length
    $itemName = $Item.Name
    if ($itemName.Length -gt 255) {
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = if ($Item.PSIsContainer) { 'Folder' } else { 'File' }
            Issue = 'FileNameTooLong'
            IssueDescription = 'File or folder name exceeds 255 character limit'
            Severity = 'Critical'
            Category = 'Path Length'
            CurrentValue = $itemName.Length
            Limit = 255
            Suggestion = "Rename to 255 characters or fewer. Current length: $($itemName.Length) chars."
        }
    }

    # Check total path length - Critical if over limit
    if ($effectiveLength -gt $MaxPathLength) {
        $overBy = $effectiveLength - $MaxPathLength
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = if ($Item.PSIsContainer) { 'Folder' } else { 'File' }
            Issue = 'PathTooLong'
            IssueDescription = "Path exceeds $MaxPathLength character limit"
            Severity = 'Critical'
            Category = 'Path Length'
            CurrentValue = $effectiveLength
            Limit = $MaxPathLength
            AvailableChars = $availableChars
            OverBy = $overBy
            Suggestion = "Shorten path by at least $overBy characters. Consider shortening folder names or reducing nesting depth."
        }
    }
    # Check if approaching limit - Warning
    elseif ($WarningThresholdPercent -gt 0) {
        $warningThreshold = [Math]::Floor($MaxPathLength * ($WarningThresholdPercent / 100))
        if ($effectiveLength -ge $warningThreshold) {
            $remaining = $MaxPathLength - $effectiveLength
            $percentUsed = [Math]::Round(($effectiveLength / $MaxPathLength) * 100)
            $issues += [PSCustomObject]@{
                Path = $Item.FullName
                Name = $itemName
                Type = if ($Item.PSIsContainer) { 'Folder' } else { 'File' }
                Issue = 'PathNearLimit'
                IssueDescription = "Path is at $percentUsed% of $MaxPathLength character limit"
                Severity = 'Warning'
                Category = 'Path Length'
                CurrentValue = $effectiveLength
                Limit = $MaxPathLength
                AvailableChars = $availableChars
                RemainingChars = $remaining
                Suggestion = "Only $remaining characters remaining. Consider shortening path to provide buffer for future growth."
            }
        }
    }

    return $issues
}

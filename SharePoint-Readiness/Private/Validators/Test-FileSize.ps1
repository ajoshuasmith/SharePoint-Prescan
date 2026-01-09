function Test-FileSize {
    <#
    .SYNOPSIS
        Tests if a file exceeds SharePoint Online size limits.

    .DESCRIPTION
        Validates file size against SharePoint Online's 250 GB limit and
        provides warnings for large files that may cause sync issues.

    .PARAMETER Item
        The file system item to test (FileInfo or DirectoryInfo object).

    .PARAMETER MaxFileSizeBytes
        Maximum allowed file size in bytes (default: 250 GB).

    .PARAMETER LargeFileThresholdBytes
        Size threshold for large file warning (default: 5 GB).

    .PARAMETER VeryLargeFileThresholdBytes
        Size threshold for very large file warning (default: 15 GB).

    .OUTPUTS
        PSCustomObject with Issue details if problems found, $null otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter()]
        [long]$MaxFileSizeBytes = 268435456000,  # 250 GB

        [Parameter()]
        [long]$LargeFileThresholdBytes = 5368709120,  # 5 GB

        [Parameter()]
        [long]$VeryLargeFileThresholdBytes = 16106127360  # ~15 GB (sync limit)
    )

    # Skip folders
    if ($Item.PSIsContainer) {
        return @()
    }

    $issues = @()
    $itemName = $Item.Name
    $fileSize = $Item.Length

    # Helper function to format file size
    function Format-Size {
        param([long]$Bytes)
        if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
        if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
        if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
        if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
        return "$Bytes bytes"
    }

    $formattedSize = Format-Size -Bytes $fileSize
    $formattedMax = Format-Size -Bytes $MaxFileSizeBytes

    # Critical: File exceeds maximum size
    if ($fileSize -gt $MaxFileSizeBytes) {
        $overBy = $fileSize - $MaxFileSizeBytes
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = 'File'
            Issue = 'FileTooLarge'
            IssueDescription = "File size ($formattedSize) exceeds SharePoint limit ($formattedMax)"
            Severity = 'Critical'
            Category = 'File Size'
            FileSize = $fileSize
            FileSizeFormatted = $formattedSize
            Limit = $MaxFileSizeBytes
            LimitFormatted = $formattedMax
            OverBy = $overBy
            Suggestion = "Split file into smaller parts, compress, or use alternative storage (Azure Blob, external drive)."
        }
    }
    # Warning: File may have sync issues (>15 GB)
    elseif ($fileSize -gt $VeryLargeFileThresholdBytes) {
        $formattedThreshold = Format-Size -Bytes $VeryLargeFileThresholdBytes
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = 'File'
            Issue = 'FileSyncMayFail'
            IssueDescription = "File size ($formattedSize) may cause sync issues (threshold: $formattedThreshold)"
            Severity = 'Warning'
            Category = 'File Size'
            FileSize = $fileSize
            FileSizeFormatted = $formattedSize
            Threshold = $VeryLargeFileThresholdBytes
            ThresholdFormatted = $formattedThreshold
            Suggestion = "Very large files may timeout during upload or sync. Consider uploading directly via browser or using SharePoint Migration Tool."
        }
    }
    # Info: Large file (>5 GB)
    elseif ($fileSize -gt $LargeFileThresholdBytes) {
        $formattedThreshold = Format-Size -Bytes $LargeFileThresholdBytes
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = 'File'
            Issue = 'LargeFile'
            IssueDescription = "Large file ($formattedSize) - may take significant time to sync"
            Severity = 'Info'
            Category = 'File Size'
            FileSize = $fileSize
            FileSizeFormatted = $formattedSize
            Threshold = $LargeFileThresholdBytes
            ThresholdFormatted = $formattedThreshold
            Suggestion = "Large files sync more slowly. Ensure stable internet connection during initial sync."
        }
    }

    return $issues
}

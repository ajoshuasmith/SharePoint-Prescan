function Test-ReservedNames {
    <#
    .SYNOPSIS
        Tests if a file or folder uses a reserved name in SharePoint Online.

    .DESCRIPTION
        Checks the item name against SharePoint Online's list of reserved names:
        - Windows reserved names: CON, PRN, AUX, NUL, COM0-COM9, LPT0-LPT9
        - SharePoint reserved: .lock, _vti_, desktop.ini, forms (at root)
        - Blocked prefixes: ~$ for files, ~ for folders

    .PARAMETER Item
        The file system item to test (FileInfo or DirectoryInfo object).

    .PARAMETER RelativePath
        The relative path from the scan root (to detect root-level items).

    .PARAMETER ReservedNames
        Array of reserved names to check.

    .PARAMETER BlockedPatterns
        Patterns that cannot appear anywhere in the name.

    .PARAMETER BlockedPrefixes
        Hashtable of blocked prefixes for files and folders.

    .OUTPUTS
        PSCustomObject with Issue details if problems found, $null otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter()]
        [string]$RelativePath = '',

        [Parameter()]
        [string[]]$ReservedNames = @(
            '.lock', 'CON', 'PRN', 'AUX', 'NUL',
            'COM0', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
            'LPT0', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
        ),

        [Parameter()]
        [string[]]$BlockedPatterns = @('_vti_'),

        [Parameter()]
        [hashtable]$BlockedPrefixes = @{
            File = @('~$')
            Folder = @('~')
        }
    )

    $issues = @()
    $itemName = $Item.Name
    $itemNameUpper = $itemName.ToUpperInvariant()
    $isFolder = $Item.PSIsContainer
    $isRootLevel = [string]::IsNullOrEmpty($RelativePath) -or ($RelativePath -eq $itemName)

    # Check for exact reserved name matches (case-insensitive)
    $nameWithoutExtension = if (-not $isFolder -and $itemName.Contains('.')) {
        [System.IO.Path]::GetFileNameWithoutExtension($itemName)
    } else {
        $itemName
    }

    foreach ($reserved in $ReservedNames) {
        if ($nameWithoutExtension -ieq $reserved -or $itemName -ieq $reserved) {
            $issues += [PSCustomObject]@{
                Path = $Item.FullName
                Name = $itemName
                Type = if ($isFolder) { 'Folder' } else { 'File' }
                Issue = 'ReservedName'
                IssueDescription = "'$itemName' is a reserved name in Windows/SharePoint"
                Severity = 'Critical'
                Category = 'Reserved Names'
                ReservedName = $reserved
                Suggestion = "Rename to avoid reserved name. Suggested: '${itemName}_file' or '${itemName}_folder'"
                SuggestedName = "${itemName}_renamed"
            }
            break
        }
    }

    # Check for blocked patterns anywhere in the name
    foreach ($pattern in $BlockedPatterns) {
        if ($itemName -ilike "*$pattern*") {
            $issues += [PSCustomObject]@{
                Path = $Item.FullName
                Name = $itemName
                Type = if ($isFolder) { 'Folder' } else { 'File' }
                Issue = 'BlockedPattern'
                IssueDescription = "Name contains blocked pattern '$pattern'"
                Severity = 'Critical'
                Category = 'Reserved Names'
                BlockedPattern = $pattern
                Suggestion = "Rename to remove '$pattern' from the name."
            }
        }
    }

    # Check for blocked prefixes
    $prefixesToCheck = if ($isFolder) { $BlockedPrefixes.Folder } else { $BlockedPrefixes.File }
    foreach ($prefix in $prefixesToCheck) {
        if ($itemName.StartsWith($prefix)) {
            $issues += [PSCustomObject]@{
                Path = $Item.FullName
                Name = $itemName
                Type = if ($isFolder) { 'Folder' } else { 'File' }
                Issue = 'BlockedPrefix'
                IssueDescription = "Name starts with blocked prefix '$prefix'"
                Severity = 'Critical'
                Category = 'Reserved Names'
                BlockedPrefix = $prefix
                Suggestion = "Rename to remove the '$prefix' prefix."
                SuggestedName = $itemName.Substring($prefix.Length)
            }
        }
    }

    # Check for 'forms' at root level (reserved by SharePoint)
    if ($isRootLevel -and $itemName -ieq 'forms' -and $isFolder) {
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = 'Folder'
            Issue = 'RootLevelReserved'
            IssueDescription = "'forms' folder name is reserved at root level of SharePoint library"
            Severity = 'Critical'
            Category = 'Reserved Names'
            Suggestion = "Rename 'forms' folder to something else, e.g., 'Forms_Data' or 'Form_Templates'"
            SuggestedName = 'Forms_Data'
        }
    }

    # Check for desktop.ini (won't sync but good to note)
    if ($itemName -ieq 'desktop.ini') {
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = 'File'
            Issue = 'SystemFile'
            IssueDescription = 'desktop.ini is a system file that will not sync'
            Severity = 'Info'
            Category = 'Reserved Names'
            Suggestion = "This file will be skipped during sync. No action needed unless folder customizations should be preserved."
        }
    }

    return $issues
}

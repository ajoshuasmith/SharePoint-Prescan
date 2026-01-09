function Test-NameConflicts {
    <#
    .SYNOPSIS
        Tests for name conflicts that would occur in SharePoint Online.

    .DESCRIPTION
        SharePoint Online is case-insensitive for file/folder names. This function
        identifies items that have the same name when compared case-insensitively,
        which would cause conflicts during migration.

    .PARAMETER Items
        Array of file system items to check for conflicts.

    .PARAMETER GroupedItems
        Pre-grouped items by parent folder (optional, for performance).

    .OUTPUTS
        Array of PSCustomObjects with Issue details for conflicting items.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Items')]
        [System.IO.FileSystemInfo[]]$Items,

        [Parameter(Mandatory, ParameterSetName = 'Grouped')]
        [hashtable]$GroupedItems
    )

    $issues = @()

    # Group items by parent folder if not already grouped
    if ($PSCmdlet.ParameterSetName -eq 'Items') {
        $GroupedItems = @{}
        foreach ($item in $Items) {
            $parentPath = $item.DirectoryName
            if (-not $parentPath) { $parentPath = $item.Parent.FullName }
            if (-not $parentPath) { $parentPath = '__ROOT__' }

            if (-not $GroupedItems.ContainsKey($parentPath)) {
                $GroupedItems[$parentPath] = @()
            }
            $GroupedItems[$parentPath] += $item
        }
    }

    # Check each folder for case-insensitive duplicates
    foreach ($folderPath in $GroupedItems.Keys) {
        $folderItems = $GroupedItems[$folderPath]

        # Group by lowercase name
        $nameGroups = @{}
        foreach ($item in $folderItems) {
            $lowerName = $item.Name.ToLowerInvariant()
            if (-not $nameGroups.ContainsKey($lowerName)) {
                $nameGroups[$lowerName] = @()
            }
            $nameGroups[$lowerName] += $item
        }

        # Find conflicts (groups with more than one item)
        foreach ($lowerName in $nameGroups.Keys) {
            $conflictingItems = $nameGroups[$lowerName]
            if ($conflictingItems.Count -gt 1) {
                # Sort by name to get consistent ordering
                $sortedItems = $conflictingItems | Sort-Object Name

                $conflictNames = ($sortedItems | ForEach-Object { "'$($_.Name)'" }) -join ', '

                foreach ($item in $sortedItems) {
                    $otherItems = $sortedItems | Where-Object { $_.FullName -ne $item.FullName }
                    $otherNames = ($otherItems | ForEach-Object { "'$($_.Name)'" }) -join ', '

                    $issues += [PSCustomObject]@{
                        Path = $item.FullName
                        Name = $item.Name
                        Type = if ($item.PSIsContainer) { 'Folder' } else { 'File' }
                        Issue = 'NameConflict'
                        IssueDescription = "Name conflicts with $otherNames (case-insensitive)"
                        Severity = 'Warning'
                        Category = 'Name Conflicts'
                        ConflictsWith = $otherItems.FullName
                        ConflictingNames = $conflictNames
                        ParentFolder = $folderPath
                        Suggestion = "Rename one of the conflicting items to be unique. SharePoint is case-insensitive."
                    }
                }
            }
        }
    }

    return $issues
}

function Find-NameConflicts {
    <#
    .SYNOPSIS
        Efficiently finds name conflicts across a collection of paths.

    .DESCRIPTION
        A more efficient method for finding conflicts when processing
        items during enumeration rather than after.

    .PARAMETER Path
        The file path to check.

    .PARAMETER Name
        The file or folder name.

    .PARAMETER IsFolder
        Whether the item is a folder.

    .PARAMETER ConflictTracker
        A hashtable used to track seen names (passed by reference).

    .OUTPUTS
        PSCustomObject with conflict details if a conflict is found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [bool]$IsFolder = $false,

        [Parameter(Mandatory)]
        [hashtable]$ConflictTracker
    )

    $parentPath = Split-Path -Parent $Path
    $lowerName = $Name.ToLowerInvariant()
    $key = "$parentPath|$lowerName"

    if ($ConflictTracker.ContainsKey($key)) {
        $existingItem = $ConflictTracker[$key]
        return [PSCustomObject]@{
            Path = $Path
            Name = $Name
            Type = if ($IsFolder) { 'Folder' } else { 'File' }
            Issue = 'NameConflict'
            IssueDescription = "Name conflicts with '$($existingItem.Name)' (case-insensitive)"
            Severity = 'Warning'
            Category = 'Name Conflicts'
            ConflictsWith = $existingItem.Path
            ParentFolder = $parentPath
            Suggestion = "Rename one of the conflicting items. SharePoint is case-insensitive."
        }
    }
    else {
        $ConflictTracker[$key] = @{
            Path = $Path
            Name = $Name
            IsFolder = $IsFolder
        }
        return $null
    }
}

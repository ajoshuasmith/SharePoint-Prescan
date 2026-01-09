function Test-SpecialFiles {
    <#
    .SYNOPSIS
        Tests for hidden, system, and other special files.

    .DESCRIPTION
        Identifies files that are hidden, system files, or have other attributes
        that may affect their behavior in SharePoint Online.

    .PARAMETER Item
        The file system item to test (FileInfo or DirectoryInfo object).

    .OUTPUTS
        PSCustomObject with Issue details if problems found, $null otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    $issues = @()
    $itemName = $Item.Name
    $isFolder = $Item.PSIsContainer
    $attributes = $Item.Attributes

    # Check for hidden files
    if ($attributes -band [System.IO.FileAttributes]::Hidden) {
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = if ($isFolder) { 'Folder' } else { 'File' }
            Issue = 'HiddenItem'
            IssueDescription = 'Item is hidden'
            Severity = 'Info'
            Category = 'Hidden/System Files'
            Attributes = $attributes.ToString()
            Suggestion = "Hidden items will sync but may be unexpected in SharePoint. Verify if this should be migrated."
        }
    }

    # Check for system files
    if ($attributes -band [System.IO.FileAttributes]::System) {
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = if ($isFolder) { 'Folder' } else { 'File' }
            Issue = 'SystemItem'
            IssueDescription = 'Item is marked as a system file'
            Severity = 'Info'
            Category = 'Hidden/System Files'
            Attributes = $attributes.ToString()
            Suggestion = "System files may not sync properly or may be skipped. Review if needed."
        }
    }

    # Check for specific system files by name
    $systemFileNames = @(
        'desktop.ini',
        '.ds_store',
        'thumbs.db',
        '.spotlight-v100',
        '.trashes',
        '.fseventsd',
        '.documentrevisions-v100',
        '.temporaryitems',
        '.apdisk',
        'hiberfil.sys',
        'pagefile.sys',
        'swapfile.sys',
        'ntuser.dat',
        'ntuser.dat.log',
        'ntuser.ini'
    )

    if ($systemFileNames -contains $itemName.ToLowerInvariant()) {
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = 'File'
            Issue = 'KnownSystemFile'
            IssueDescription = 'Known system file that typically should not be migrated'
            Severity = 'Info'
            Category = 'Hidden/System Files'
            Suggestion = "This file is a system file and will typically be skipped during sync. No action needed."
        }
    }

    # Check for empty folders
    if ($isFolder) {
        try {
            $hasChildren = [System.IO.Directory]::EnumerateFileSystemEntries($Item.FullName) | Select-Object -First 1
            if (-not $hasChildren) {
                $issues += [PSCustomObject]@{
                    Path = $Item.FullName
                    Name = $itemName
                    Type = 'Folder'
                    Issue = 'EmptyFolder'
                    IssueDescription = 'Folder is empty'
                    Severity = 'Info'
                    Category = 'Hidden/System Files'
                    Suggestion = "Empty folders may not sync to SharePoint unless they contain at least one file. Consider if this folder is needed."
                }
            }
        }
        catch {
            # Access denied or other error - skip empty check
        }
    }

    # Check for reparse points (symlinks, junctions)
    if ($attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        $issues += [PSCustomObject]@{
            Path = $Item.FullName
            Name = $itemName
            Type = if ($isFolder) { 'Folder' } else { 'File' }
            Issue = 'ReparsePoint'
            IssueDescription = 'Item is a symbolic link or junction point'
            Severity = 'Warning'
            Category = 'Hidden/System Files'
            Attributes = $attributes.ToString()
            Suggestion = "Symbolic links and junctions will not sync properly. The link target should be migrated instead."
        }
    }

    # Check for Unix-style hidden files (starting with .)
    if ($itemName.StartsWith('.') -and $itemName.Length -gt 1 -and $itemName -ne '..') {
        # Skip if already flagged as hidden
        $alreadyFlagged = $issues | Where-Object { $_.Issue -eq 'HiddenItem' }
        if (-not $alreadyFlagged) {
            # Common developer/config files starting with .
            $devConfigFiles = @(
                '.gitignore', '.gitattributes', '.gitmodules',
                '.env', '.env.local', '.env.development', '.env.production',
                '.editorconfig', '.eslintrc', '.prettierrc', '.babelrc',
                '.npmrc', '.nvmrc', '.yarnrc',
                '.dockerignore', '.travis.yml',
                '.htaccess', '.htpasswd'
            )

            $severity = if ($devConfigFiles -contains $itemName.ToLowerInvariant()) { 'Info' } else { 'Info' }

            $issues += [PSCustomObject]@{
                Path = $Item.FullName
                Name = $itemName
                Type = if ($isFolder) { 'Folder' } else { 'File' }
                Issue = 'UnixHiddenItem'
                IssueDescription = 'Item uses Unix-style hidden naming (starts with dot)'
                Severity = $severity
                Category = 'Hidden/System Files'
                Suggestion = "Unix-style hidden files (starting with .) will sync but may be configuration files. Verify if migration is intended."
            }
        }
    }

    return $issues
}

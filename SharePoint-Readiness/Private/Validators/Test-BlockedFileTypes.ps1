function Test-BlockedFileTypes {
    <#
    .SYNOPSIS
        Tests if a file has an extension that is blocked in SharePoint Online.

    .DESCRIPTION
        Checks the file extension against lists of blocked and restricted file types
        in SharePoint Online, including executables, scripts, and system files.

    .PARAMETER Item
        The file system item to test (FileInfo or DirectoryInfo object).

    .PARAMETER BlockedFileTypesConfig
        Hashtable containing blocked file type configurations.

    .OUTPUTS
        PSCustomObject with Issue details if problems found, $null otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter()]
        [hashtable]$BlockedFileTypesConfig
    )

    # Skip folders
    if ($Item.PSIsContainer) {
        return @()
    }

    $issues = @()
    $itemName = $Item.Name
    $extension = $Item.Extension.ToLowerInvariant()

    # Skip if no extension
    if ([string]::IsNullOrEmpty($extension)) {
        return @()
    }

    # Default blocked file types if config not provided
    if (-not $BlockedFileTypesConfig) {
        $BlockedFileTypesConfig = @{
            Executables = @{
                Extensions = @('.exe', '.bat', '.cmd', '.com', '.scr', '.pif', '.msi', '.msp')
                Severity = 'Warning'
                Message = 'Executable files are often blocked by SharePoint administrators.'
            }
            Scripts = @{
                Extensions = @('.vbs', '.vbe', '.js', '.jse', '.wsf', '.wsh', '.ps1', '.psm1')
                Severity = 'Warning'
                Message = 'Script files may be blocked by SharePoint administrators.'
            }
            System = @{
                Extensions = @('.dll', '.sys', '.drv', '.cpl', '.ocx')
                Severity = 'Warning'
                Message = 'System files are typically blocked in SharePoint Online.'
            }
        }
    }

    # Check each category of blocked files
    foreach ($category in $BlockedFileTypesConfig.Keys) {
        $config = $BlockedFileTypesConfig[$category]

        # Skip if no extensions defined
        if (-not $config.Extensions) {
            continue
        }

        # Check if extension matches
        if ($config.Extensions -contains $extension) {
            $severity = if ($config.Severity) { $config.Severity } else { 'Warning' }
            $message = if ($config.Message) { $config.Message } else { "File type '$extension' may be blocked." }

            $issues += [PSCustomObject]@{
                Path = $Item.FullName
                Name = $itemName
                Type = 'File'
                Issue = 'BlockedFileType'
                IssueDescription = $message
                Severity = $severity
                Category = 'Blocked File Types'
                FileExtension = $extension
                BlockedCategory = $category
                Suggestion = "Move to a non-synced location, or request IT to allow this file type in SharePoint admin settings."
            }

            # Only report first match
            break
        }

        # Check patterns if defined
        if ($config.Patterns) {
            foreach ($pattern in $config.Patterns) {
                if ($itemName -like $pattern) {
                    $severity = if ($config.Severity) { $config.Severity } else { 'Info' }
                    $message = if ($config.Message) { $config.Message } else { "File matches blocked pattern '$pattern'." }

                    $issues += [PSCustomObject]@{
                        Path = $Item.FullName
                        Name = $itemName
                        Type = 'File'
                        Issue = 'BlockedFilePattern'
                        IssueDescription = $message
                        Severity = $severity
                        Category = 'Blocked File Types'
                        MatchedPattern = $pattern
                        BlockedCategory = $category
                        Suggestion = "This file type typically doesn't sync to SharePoint."
                    }
                    break
                }
            }
        }
    }

    return $issues
}

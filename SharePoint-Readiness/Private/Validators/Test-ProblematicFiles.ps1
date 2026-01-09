function Test-ProblematicFiles {
    <#
    .SYNOPSIS
        Tests if a file is a known problematic type for SharePoint Online.

    .DESCRIPTION
        Identifies files that will upload to SharePoint but have known issues with
        syncing, collaboration, or functionality. This includes CAD files, Adobe
        Creative Suite files, databases, PST files, and more.

    .PARAMETER Item
        The file system item to test (FileInfo or DirectoryInfo object).

    .PARAMETER RelativePath
        The relative path from the scan root.

    .PARAMETER DestinationPathLength
        The character count of the SharePoint destination path.

    .PARAMETER ProblematicTypesConfig
        Hashtable containing problematic file type configurations.

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
        [int]$DestinationPathLength = 0,

        [Parameter()]
        [hashtable]$ProblematicTypesConfig
    )

    $issues = @()
    $itemName = $Item.Name
    $isFolder = $Item.PSIsContainer

    # Default config if not provided
    if (-not $ProblematicTypesConfig) {
        $ProblematicTypesConfig = @{
            CAD = @{
                Extensions = @('.dwg', '.dxf', '.rvt', '.rfa', '.dgn', '.sldprt', '.sldasm')
                Severity = 'Warning'
                Category = 'CAD/BIM'
                Message = 'CAD files lack proper file locking in SharePoint. Multiple users can edit simultaneously without warning.'
            }
            Adobe = @{
                Extensions = @('.psd', '.ai', '.indd', '.prproj', '.aep')
                Severity = 'Warning'
                Category = 'Adobe Creative'
                Message = 'Adobe files cannot be opened directly from SharePoint. Linked files will break across users.'
            }
            Database = @{
                Extensions = @('.mdb', '.accdb', '.qbw', '.qbb', '.sqlite', '.db')
                Severity = 'Warning'
                Category = 'Database'
                Message = 'Database files may corrupt when accessed by multiple users through sync.'
            }
        }
    }

    # Check for folder patterns (like node_modules, .git)
    if ($isFolder) {
        foreach ($category in $ProblematicTypesConfig.Keys) {
            $config = $ProblematicTypesConfig[$category]

            if ($config.FolderPatterns) {
                foreach ($pattern in $config.FolderPatterns) {
                    if ($itemName -ieq $pattern -or $itemName -ilike $pattern) {
                        $severity = if ($config.Severity) { $config.Severity } else { 'Warning' }
                        $categoryName = if ($config.Category) { $config.Category } else { $category }
                        $message = if ($config.Message) { $config.Message } else { "Folder '$itemName' may cause sync issues." }

                        $issues += [PSCustomObject]@{
                            Path = $Item.FullName
                            Name = $itemName
                            Type = 'Folder'
                            Issue = 'ProblematicFolder'
                            IssueDescription = $message
                            Severity = $severity
                            Category = $categoryName
                            ProblematicType = $category
                            Suggestion = "Exclude this folder from migration or delete if not needed."
                        }
                        break
                    }
                }
            }

            # Check for secret file patterns
            if ($config.Patterns -and -not $isFolder) {
                foreach ($pattern in $config.Patterns) {
                    if ($itemName -ilike $pattern) {
                        $severity = if ($config.Severity) { $config.Severity } else { 'Warning' }
                        $categoryName = if ($config.Category) { $config.Category } else { $category }
                        $message = if ($config.Message) { $config.Message } else { "File matches problematic pattern." }

                        $issues += [PSCustomObject]@{
                            Path = $Item.FullName
                            Name = $itemName
                            Type = 'File'
                            Issue = 'ProblematicFile'
                            IssueDescription = $message
                            Severity = $severity
                            Category = $categoryName
                            ProblematicType = $category
                            MatchedPattern = $pattern
                            Suggestion = "Review this file before migration."
                        }
                        break
                    }
                }
            }
        }
        return $issues
    }

    # For files, check extension
    $extension = $Item.Extension.ToLowerInvariant()
    if ([string]::IsNullOrEmpty($extension)) {
        return @()
    }

    foreach ($category in $ProblematicTypesConfig.Keys) {
        $config = $ProblematicTypesConfig[$category]

        # Skip folder-only configs
        if (-not $config.Extensions) {
            continue
        }

        # Handle the "Other" category with hashtable extensions
        if ($config.Extensions -is [hashtable]) {
            if ($config.Extensions.ContainsKey($extension)) {
                $specificMessage = $config.Extensions[$extension]
                $issues += [PSCustomObject]@{
                    Path = $Item.FullName
                    Name = $itemName
                    Type = 'File'
                    Issue = 'ProblematicFile'
                    IssueDescription = $specificMessage
                    Severity = 'Info'
                    Category = 'Other'
                    FileExtension = $extension
                    ProblematicType = $category
                    Suggestion = "Be aware of limitations with this file type in SharePoint."
                }
            }
            continue
        }

        # Standard extension array check
        if ($config.Extensions -contains $extension) {
            $severity = if ($config.Severity) { $config.Severity } else { 'Warning' }
            $categoryName = if ($config.Category) { $config.Category } else { $category }
            $message = if ($config.Message) { $config.Message } else { "File type '$extension' has known issues in SharePoint." }

            # Special handling for Bluebeam (only warn on long paths)
            if ($category -eq 'Bluebeam' -and $config.OnlyWarnOnLongPaths) {
                $pathThreshold = if ($config.PathThresholdChars) { $config.PathThresholdChars } else { 200 }
                $totalPathLength = $DestinationPathLength + $RelativePath.Length

                if ($totalPathLength -lt $pathThreshold) {
                    continue  # Skip if path is short enough
                }

                $message = "Bluebeam Revu has a 260-character path limit. Current path ($totalPathLength chars) may cause issues."
            }

            # Check file size thresholds if defined
            $sizeWarning = $null
            if ($config.SizeThresholdBytes -and $Item.Length -gt $config.SizeThresholdBytes) {
                $sizeGB = [Math]::Round($Item.Length / 1GB, 2)
                $thresholdGB = [Math]::Round($config.SizeThresholdBytes / 1GB, 2)
                $sizeWarning = " File is ${sizeGB}GB (threshold: ${thresholdGB}GB)."
            }

            if ($config.SizeWarningBytes -and $Item.Length -gt $config.SizeWarningBytes) {
                $sizeGB = [Math]::Round($Item.Length / 1GB, 2)
                $sizeWarning = " Large file: ${sizeGB}GB - sync may be slow."
            }

            # Build suggestion based on category
            $suggestion = switch ($categoryName) {
                'CAD/BIM' { "Consider using Autodesk Docs/BIM Collaborate Pro for collaborative CAD work, or keep on traditional file server." }
                'Adobe Creative' { "Users must download to local drive to edit. For InDesign, ensure all team members sync to identical folder paths." }
                'Database' { "Migrate to cloud-native solution: SharePoint Lists, Power Apps, SQL Azure, or QuickBooks Online." }
                'Email Archive' { "Migrate mailbox data to Exchange Online archive instead of syncing PST files." }
                'Large Media' { "Consider Microsoft Stream for video hosting, or Azure blob storage for large media." }
                'Security' { "Review file contents for secrets/credentials before migrating to shared storage." }
                'Virtual Machine' { "VM images should be stored in Azure blob storage, not SharePoint." }
                default { "Review before migration - this file type has known limitations in SharePoint." }
            }

            $issues += [PSCustomObject]@{
                Path = $Item.FullName
                Name = $itemName
                Type = 'File'
                Issue = 'ProblematicFile'
                IssueDescription = $message + $sizeWarning
                Severity = $severity
                Category = $categoryName
                FileExtension = $extension
                ProblematicType = $category
                FileSize = $Item.Length
                Suggestion = $suggestion
            }
        }
    }

    return $issues
}

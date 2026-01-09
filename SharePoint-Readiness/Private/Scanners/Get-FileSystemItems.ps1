function Get-FileSystemItems {
    <#
    .SYNOPSIS
        Recursively enumerates all files and folders in a path.

    .DESCRIPTION
        Efficiently enumerates all files and folders in the specified path,
        handling access denied errors gracefully and providing progress updates.

    .PARAMETER Path
        The root path to scan.

    .PARAMETER ExcludePaths
        Array of paths to exclude from scanning.

    .PARAMETER ExcludeFolders
        Array of folder names to exclude (e.g., '$RECYCLE.BIN').

    .PARAMETER MaxItems
        Maximum number of items to enumerate (0 = unlimited).

    .PARAMETER ProgressCallback
        Script block to call for progress updates. Receives item count as parameter.

    .OUTPUTS
        Yields FileInfo and DirectoryInfo objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string[]]$ExcludePaths = @(),

        [Parameter()]
        [string[]]$ExcludeFolders = @('$RECYCLE.BIN', 'System Volume Information', 'RECYCLER'),

        [Parameter()]
        [int]$MaxItems = 0,

        [Parameter()]
        [scriptblock]$ProgressCallback
    )

    # Normalize paths for comparison
    $Path = $Path.TrimEnd('\', '/')
    $normalizedExcludes = $ExcludePaths | ForEach-Object { $_.TrimEnd('\', '/').ToLowerInvariant() }

    # Track enumeration
    $itemCount = 0
    $errorCount = 0
    $errors = @()

    # Use a stack for non-recursive enumeration (more memory efficient)
    $folderStack = [System.Collections.Generic.Stack[string]]::new()
    $folderStack.Push($Path)

    while ($folderStack.Count -gt 0) {
        $currentFolder = $folderStack.Pop()

        # Check if we've hit max items
        if ($MaxItems -gt 0 -and $itemCount -ge $MaxItems) {
            break
        }

        try {
            # Get directory info for current folder
            $dirInfo = [System.IO.DirectoryInfo]::new($currentFolder)

            # Skip excluded folders by name
            if ($ExcludeFolders -contains $dirInfo.Name) {
                continue
            }

            # Skip excluded paths
            if ($normalizedExcludes -contains $currentFolder.ToLowerInvariant()) {
                continue
            }

            # Yield the folder itself (unless it's the root)
            if ($currentFolder -ne $Path) {
                $itemCount++
                [PSCustomObject]@{
                    Item = $dirInfo
                    RelativePath = $currentFolder.Substring($Path.Length).TrimStart('\', '/')
                    ItemNumber = $itemCount
                }

                # Progress callback
                if ($ProgressCallback -and ($itemCount % 100 -eq 0)) {
                    & $ProgressCallback $itemCount
                }
            }

            # Enumerate files in current folder
            $files = [System.IO.Directory]::EnumerateFiles($currentFolder)
            foreach ($filePath in $files) {
                if ($MaxItems -gt 0 -and $itemCount -ge $MaxItems) {
                    break
                }

                try {
                    $fileInfo = [System.IO.FileInfo]::new($filePath)
                    $itemCount++

                    [PSCustomObject]@{
                        Item = $fileInfo
                        RelativePath = $filePath.Substring($Path.Length).TrimStart('\', '/')
                        ItemNumber = $itemCount
                    }

                    # Progress callback
                    if ($ProgressCallback -and ($itemCount % 100 -eq 0)) {
                        & $ProgressCallback $itemCount
                    }
                }
                catch {
                    $errorCount++
                    $errors += [PSCustomObject]@{
                        Path = $filePath
                        Error = $_.Exception.Message
                    }
                }
            }

            # Add subdirectories to stack (in reverse order to maintain expected order)
            $subDirs = [System.IO.Directory]::EnumerateDirectories($currentFolder)
            $subDirList = [System.Collections.Generic.List[string]]::new()
            foreach ($subDir in $subDirs) {
                $dirName = [System.IO.Path]::GetFileName($subDir)
                if ($ExcludeFolders -notcontains $dirName) {
                    $subDirList.Add($subDir)
                }
            }

            # Add in reverse to process in expected order
            for ($i = $subDirList.Count - 1; $i -ge 0; $i--) {
                $folderStack.Push($subDirList[$i])
            }
        }
        catch [System.UnauthorizedAccessException] {
            $errorCount++
            $errors += [PSCustomObject]@{
                Path = $currentFolder
                Error = "Access denied"
            }
        }
        catch {
            $errorCount++
            $errors += [PSCustomObject]@{
                Path = $currentFolder
                Error = $_.Exception.Message
            }
        }
    }

    # Final progress callback
    if ($ProgressCallback) {
        & $ProgressCallback $itemCount
    }

    # Return summary info as last item
    [PSCustomObject]@{
        Item = $null
        Summary = $true
        TotalItems = $itemCount
        ErrorCount = $errorCount
        Errors = $errors
    }
}

function Get-FileSystemItemsFast {
    <#
    .SYNOPSIS
        High-performance file system enumeration using robocopy /L.

    .DESCRIPTION
        Uses robocopy in list-only mode for very fast enumeration of large
        directories. Falls back to .NET enumeration if robocopy unavailable.

    .PARAMETER Path
        The root path to scan.

    .PARAMETER ExcludeFolders
        Array of folder names to exclude.

    .OUTPUTS
        Array of file/folder paths with metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string[]]$ExcludeFolders = @('$RECYCLE.BIN', 'System Volume Information')
    )

    # Check if robocopy is available
    $robocopyPath = Get-Command robocopy -ErrorAction SilentlyContinue

    if ($robocopyPath) {
        # Build exclude parameters
        $excludeParams = $ExcludeFolders | ForEach-Object { "/XD `"$_`"" }

        # Run robocopy in list-only mode
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            $robocopyArgs = @(
                "`"$Path`""
                "`"C:\FAKEPATH`""
                '/L'           # List only
                '/E'           # Include subdirectories
                '/NJH'         # No job header
                '/NJS'         # No job summary
                '/NC'          # No class
                '/NDL'         # No directory list
                '/NS'          # No size
                '/FP'          # Full path
            ) + $excludeParams

            $output = & robocopy @robocopyArgs 2>$null
            return $output | Where-Object { $_ -match '\S' }
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
    else {
        # Fall back to .NET enumeration
        return Get-FileSystemItems -Path $Path -ExcludeFolders $ExcludeFolders
    }
}

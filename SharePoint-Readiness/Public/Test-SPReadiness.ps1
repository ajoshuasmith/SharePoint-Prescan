function Test-SPReadiness {
    <#
    .SYNOPSIS
        Scans a file path for SharePoint Online migration readiness.

    .DESCRIPTION
        Analyzes files and folders to identify issues that could cause problems
        when migrating to SharePoint Online, including:
        - Path length violations (400 character limit)
        - Invalid characters in file/folder names
        - Reserved/blocked file names
        - Blocked and problematic file types
        - File size limits (250 GB)
        - Name conflicts (case-insensitive)
        - Hidden and system files

    .PARAMETER Path
        The root path to scan. Required.

    .PARAMETER DestinationUrl
        The SharePoint destination URL. Used to calculate available path length.
        Example: https://contoso.sharepoint.com/sites/ProjectX/Shared Documents

    .PARAMETER OutputPath
        Directory to save reports. Defaults to current directory.

    .PARAMETER OutputFormat
        Report formats to generate. Options: HTML, CSV, JSON, All.
        Default: HTML, CSV

    .PARAMETER WarningThreshold
        Percentage of path limit to trigger warning (default: 80).

    .PARAMETER ExcludePath
        Paths to exclude from scanning (full paths).

    .PARAMETER Interactive
        Run in interactive mode with prompts. Default if no parameters provided.

    .PARAMETER NoProgress
        Suppress progress output.

    .PARAMETER PassThru
        Return results object instead of just writing reports.

    .EXAMPLE
        Test-SPReadiness -Path "C:\FileServer\Data" -DestinationUrl "https://contoso.sharepoint.com/sites/Project/Documents"

    .EXAMPLE
        Test-SPReadiness
        # Runs in interactive mode with prompts

    .EXAMPLE
        Test-SPReadiness -Path "D:\Shared" -DestinationUrl "https://tenant.sharepoint.com/sites/HR/Shared Documents" -OutputFormat All -PassThru
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Scripted', Position = 0)]
        [Parameter(ParameterSetName = 'Interactive')]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$Path,

        [Parameter(ParameterSetName = 'Scripted')]
        [Parameter(ParameterSetName = 'Interactive')]
        [string]$DestinationUrl,

        [Parameter()]
        [string]$OutputPath = (Get-Location).Path,

        [Parameter()]
        [ValidateSet('HTML', 'CSV', 'JSON', 'All')]
        [string[]]$OutputFormat = @('HTML', 'CSV'),

        [Parameter()]
        [ValidateRange(50, 99)]
        [int]$WarningThreshold = 80,

        [Parameter()]
        [string[]]$ExcludePath = @(),

        [Parameter(ParameterSetName = 'Interactive')]
        [switch]$Interactive,

        [Parameter()]
        [switch]$NoProgress,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        # Get module root for loading configs
        $moduleRoot = $PSScriptRoot | Split-Path -Parent | Split-Path -Parent

        # Load configurations
        $spoLimits = Import-PowerShellDataFile -Path (Join-Path $moduleRoot 'Config\SPO-Limits.psd1')
        $blockedTypes = Import-PowerShellDataFile -Path (Join-Path $moduleRoot 'Config\BlockedFileTypes.psd1')
        $problematicTypes = Import-PowerShellDataFile -Path (Join-Path $moduleRoot 'Config\ProblematicFileTypes.psd1')
        $defaultSettings = Import-PowerShellDataFile -Path (Join-Path $moduleRoot 'Config\DefaultSettings.psd1')

        # Expand 'All' output format
        if ('All' -in $OutputFormat) {
            $OutputFormat = @('HTML', 'CSV', 'JSON')
        }
    }

    process {
        # Show banner
        Write-Banner -Version "1.0.0"

        # Interactive mode: prompt for inputs
        if (-not $Path -or $Interactive) {
            Write-Host ""

            # Get source path
            if (-not $Path) {
                $Path = Read-UserInput -Prompt "Source path to scan" -Required -IsPath
            }

            # Get destination URL
            if (-not $DestinationUrl) {
                $DestinationUrl = Read-UserInput -Prompt "SharePoint destination URL" -Required -IsUrl
            }

            # Show destination info
            $destInfo = Measure-DestinationPath -DestinationUrl $DestinationUrl
            Write-Host ""
            Write-Host "    Destination path uses " -NoNewline -ForegroundColor Gray
            Write-Host "$($destInfo.EffectiveLength)" -NoNewline -ForegroundColor Cyan
            Write-Host " of 400 characters" -ForegroundColor Gray
            Write-Host "    Files can use up to " -NoNewline -ForegroundColor Gray
            Write-Host "$($destInfo.AvailableChars)" -NoNewline -ForegroundColor Green
            Write-Host " characters for their relative path" -ForegroundColor Gray
            Write-Host ""

            # Get output directory
            $defaultOutput = Join-Path (Get-Location).Path "SP-Readiness-Reports"
            $OutputPath = Read-UserInput -Prompt "Output directory" -Default $defaultOutput

            # Get output formats
            $formatOptions = @('HTML', 'CSV', 'JSON')
            Write-Host ""
            Write-Host "  ? Select output formats (comma-separated numbers, or 'all'): " -ForegroundColor Cyan
            for ($i = 0; $i -lt $formatOptions.Count; $i++) {
                Write-Host "    [$($i + 1)] $($formatOptions[$i])" -ForegroundColor White
            }
            Write-Host ""
            $formatInput = Read-Host "  Selection [1,2]"
            if ($formatInput -ieq 'all') {
                $OutputFormat = $formatOptions
            }
            elseif ($formatInput) {
                $indices = $formatInput -split ',' | ForEach-Object { ([int]$_.Trim()) - 1 }
                $OutputFormat = $indices | Where-Object { $_ -ge 0 -and $_ -lt $formatOptions.Count } | ForEach-Object { $formatOptions[$_] }
            }
            if (-not $OutputFormat) {
                $OutputFormat = @('HTML', 'CSV')
            }

            Write-Host ""
        }
        else {
            # Non-interactive: validate and show destination info
            if ($DestinationUrl) {
                $destInfo = Measure-DestinationPath -DestinationUrl $DestinationUrl
            }
            else {
                # Default destination info if not provided
                $destInfo = [PSCustomObject]@{
                    EffectiveLength = 50  # Assume 50 chars for destination
                    AvailableChars = 350
                }
                Write-Host "  Note: No destination URL provided. Using default 50-character estimate." -ForegroundColor Yellow
            }
        }

        # Create output directory if needed
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        # Initialize results
        $scanStart = Get-Date
        $allIssues = [System.Collections.Generic.List[PSCustomObject]]::new()
        $totalSize = 0
        $itemCount = 0
        $conflictTracker = @{}

        # Combine exclude paths
        $excludePaths = $ExcludePath + $defaultSettings.DefaultExcludeFolders

        Write-Host ""
        Write-Section -Title "Scanning: $Path" -Icon ">"
        Write-Host ""

        # Phase 1: Enumerate files
        Write-Host "    Enumerating files and folders..." -ForegroundColor Gray

        $items = [System.Collections.Generic.List[PSCustomObject]]::new()
        $enumErrors = @()

        foreach ($result in Get-FileSystemItems -Path $Path -ExcludeFolders $excludePaths) {
            if ($result.Summary) {
                # Final summary from enumerator
                $enumErrors = $result.Errors
                break
            }

            $items.Add($result)
            $itemCount++

            if (-not $NoProgress -and ($itemCount % 500 -eq 0)) {
                Write-SPProgress -Activity "Enumerating" -CurrentItem $itemCount -NoNewLine
            }
        }

        if (-not $NoProgress) {
            Write-SPProgress -Activity "Enumerating" -CurrentItem $itemCount -PercentComplete 100 -Complete
        }

        Write-Host "    Found " -NoNewline -ForegroundColor Gray
        Write-Host ("{0:N0}" -f $itemCount) -NoNewline -ForegroundColor Cyan
        Write-Host " items" -ForegroundColor Gray
        Write-Host ""

        # Phase 2: Run validation checks
        Write-Host "    Running validation checks..." -ForegroundColor Gray

        $checkCount = 0
        $totalChecks = $items.Count

        foreach ($itemData in $items) {
            $item = $itemData.Item
            $relativePath = $itemData.RelativePath

            $checkCount++

            if (-not $NoProgress -and ($checkCount % 500 -eq 0)) {
                $percent = [Math]::Round(($checkCount / $totalChecks) * 100)
                Write-SPProgress -Activity "Validating" -CurrentItem $checkCount -TotalItems $totalChecks -PercentComplete $percent -NoNewLine
            }

            # Track total size
            if (-not $item.PSIsContainer) {
                $totalSize += $item.Length
            }

            # Run all validators
            $issues = @()

            # 1. Path Length
            $issues += Test-PathLength -Item $item -RelativePath $relativePath `
                -DestinationPathLength $destInfo.EffectiveLength `
                -MaxPathLength $spoLimits.MaxPathLength `
                -WarningThresholdPercent $WarningThreshold

            # 2. Invalid Characters
            $issues += Test-InvalidCharacters -Item $item -InvalidCharacters $spoLimits.InvalidCharacters

            # 3. Reserved Names
            $issues += Test-ReservedNames -Item $item -RelativePath $relativePath `
                -ReservedNames $spoLimits.ReservedNames `
                -BlockedPatterns $spoLimits.BlockedPatterns `
                -BlockedPrefixes $spoLimits.BlockedPrefixes

            # 4. Blocked File Types
            $issues += Test-BlockedFileTypes -Item $item -BlockedFileTypesConfig $blockedTypes

            # 5. Problematic Files
            $issues += Test-ProblematicFiles -Item $item -RelativePath $relativePath `
                -DestinationPathLength $destInfo.EffectiveLength `
                -ProblematicTypesConfig $problematicTypes

            # 6. File Size
            $issues += Test-FileSize -Item $item `
                -MaxFileSizeBytes $spoLimits.MaxFileSizeBytes `
                -LargeFileThresholdBytes $defaultSettings.FileSizeWarnings.Large `
                -VeryLargeFileThresholdBytes $defaultSettings.FileSizeWarnings.VeryLarge

            # 7. Name Conflicts (tracked incrementally)
            $conflict = Find-NameConflicts -Path $item.FullName -Name $item.Name `
                -IsFolder $item.PSIsContainer -ConflictTracker $conflictTracker
            if ($conflict) {
                $issues += $conflict
            }

            # 8. Special Files (Hidden/System)
            $issues += Test-SpecialFiles -Item $item

            # Add non-null issues to results
            foreach ($issue in $issues) {
                if ($issue) {
                    $allIssues.Add($issue)
                }
            }
        }

        if (-not $NoProgress) {
            Write-SPProgress -Activity "Validating" -CurrentItem $totalChecks -TotalItems $totalChecks -PercentComplete 100 -Complete
        }

        Write-Host "    Completed " -NoNewline -ForegroundColor Gray
        Write-Host "8" -NoNewline -ForegroundColor Cyan
        Write-Host " validation checks" -ForegroundColor Gray
        Write-Host ""

        # Calculate scan duration
        $scanEnd = Get-Date
        $scanDuration = $scanEnd - $scanStart

        # Build results object
        $scanResults = [PSCustomObject]@{
            SourcePath = $Path
            DestinationUrl = $DestinationUrl
            DestinationPathLength = $destInfo.EffectiveLength
            AvailablePathChars = $destInfo.AvailableChars
            ScanDate = $scanStart
            Duration = $scanDuration
            TotalItems = $itemCount
            TotalSize = $totalSize
            Issues = $allIssues.ToArray()
            EnumerationErrors = $enumErrors
            Settings = @{
                WarningThreshold = $WarningThreshold
                OutputFormats = $OutputFormat
            }
        }

        # Phase 3: Generate reports
        Write-Host "    Generating reports..." -ForegroundColor Gray

        $reportPaths = @{}
        $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $baseName = "SP-Readiness_$timestamp"

        if ('HTML' -in $OutputFormat) {
            $htmlPath = Join-Path $OutputPath "$baseName.html"
            New-HtmlReport -ScanResults $scanResults -OutputPath $htmlPath
            $reportPaths['HTML'] = $htmlPath
        }

        if ('CSV' -in $OutputFormat) {
            $csvPath = Join-Path $OutputPath "$baseName.csv"
            New-CsvReport -ScanResults $scanResults -OutputPath $csvPath
            $reportPaths['CSV'] = $csvPath
        }

        if ('JSON' -in $OutputFormat) {
            $jsonPath = Join-Path $OutputPath "$baseName.json"
            New-JsonReport -ScanResults $scanResults -OutputPath $jsonPath
            $reportPaths['JSON'] = $jsonPath
        }

        Write-Host "    Generated " -NoNewline -ForegroundColor Gray
        Write-Host "$($reportPaths.Count)" -NoNewline -ForegroundColor Cyan
        Write-Host " report(s)" -ForegroundColor Gray

        # Show summary
        Write-Summary -ScanResults $scanResults

        # Show report paths
        Write-ReportPaths -ReportPaths $reportPaths

        # Return results if requested
        if ($PassThru) {
            $scanResults | Add-Member -NotePropertyName 'ReportPaths' -NotePropertyValue $reportPaths
            return $scanResults
        }
    }
}

# Alias for convenience
Set-Alias -Name spready -Value Test-SPReadiness -Scope Global

function Write-Summary {
    <#
    .SYNOPSIS
        Displays the scan summary with issue counts and readiness score.

    .DESCRIPTION
        Shows a formatted summary dashboard with total counts, issues by severity,
        and a readiness score visualization.

    .PARAMETER ScanResults
        The scan results object containing all issues and metadata.

    .PARAMETER NoColor
        If true, displays without colors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ScanResults,

        [Parameter()]
        [switch]$NoColor
    )

    $separator = "  " + ("=" * 60)

    # Calculate readiness score
    $totalItems = $ScanResults.TotalItems
    $criticalCount = ($ScanResults.Issues | Where-Object { $_.Severity -eq 'Critical' }).Count
    $warningCount = ($ScanResults.Issues | Where-Object { $_.Severity -eq 'Warning' }).Count
    $infoCount = ($ScanResults.Issues | Where-Object { $_.Severity -eq 'Info' }).Count

    # Score calculation: Start at 100, deduct for issues
    # Critical: -2 points each (max 50 point deduction)
    # Warning: -0.5 points each (max 25 point deduction)
    $criticalDeduction = [Math]::Min(50, $criticalCount * 2)
    $warningDeduction = [Math]::Min(25, $warningCount * 0.5)
    $readinessScore = [Math]::Max(0, 100 - $criticalDeduction - $warningDeduction)
    $readinessScore = [Math]::Round($readinessScore)

    # Determine score color
    $scoreColor = if ($readinessScore -ge 90) { 'Green' }
                  elseif ($readinessScore -ge 70) { 'Yellow' }
                  elseif ($readinessScore -ge 50) { 'DarkYellow' }
                  else { 'Red' }

    Write-Host ""
    Write-Host $separator -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "                         SCAN COMPLETE" -ForegroundColor Green
    Write-Host ""
    Write-Host $separator -ForegroundColor DarkGray
    Write-Host ""

    # Summary stats
    Write-Host "    Summary" -ForegroundColor White
    Write-Host "    ───────────────────────" -ForegroundColor DarkGray

    Write-Host "    Total Items Scanned:  " -NoNewline -ForegroundColor Gray
    Write-Host ("{0:N0}" -f $totalItems) -ForegroundColor White

    Write-Host "    Total Size:           " -NoNewline -ForegroundColor Gray
    Write-Host (Format-FileSize -Bytes $ScanResults.TotalSize) -ForegroundColor White

    Write-Host "    Scan Duration:        " -NoNewline -ForegroundColor Gray
    Write-Host "$($ScanResults.Duration.ToString('mm\:ss'))" -ForegroundColor White

    Write-Host ""

    # Readiness Score visualization
    Write-Host "    Readiness Score" -ForegroundColor White
    Write-Host "    ───────────────────────" -ForegroundColor DarkGray

    $scoreBarWidth = 20
    $filledWidth = [Math]::Round($scoreBarWidth * ($readinessScore / 100))
    $emptyWidth = $scoreBarWidth - $filledWidth
    $scoreBar = ([char]0x2588).ToString() * $filledWidth + ([char]0x2591).ToString() * $emptyWidth

    Write-Host "    " -NoNewline
    Write-Host $scoreBar -NoNewline -ForegroundColor $scoreColor
    Write-Host "  " -NoNewline
    Write-Host "$readinessScore%" -ForegroundColor $scoreColor

    Write-Host ""

    # Issue counts
    Write-Host $separator -ForegroundColor DarkGray
    Write-Host ""

    # Critical
    $criticalIcon = [char]0x25CF  # ●
    Write-Host "    $criticalIcon " -NoNewline -ForegroundColor Red
    Write-Host "Critical Issues:     " -NoNewline -ForegroundColor Gray
    Write-Host ("{0,5:N0}" -f $criticalCount) -NoNewline -ForegroundColor Red
    Write-Host "  (Must fix before migration)" -ForegroundColor DarkGray

    # Warning
    Write-Host "    $criticalIcon " -NoNewline -ForegroundColor Yellow
    Write-Host "Warnings:            " -NoNewline -ForegroundColor Gray
    Write-Host ("{0,5:N0}" -f $warningCount) -NoNewline -ForegroundColor Yellow
    Write-Host "  (Review recommended)" -ForegroundColor DarkGray

    # Info
    Write-Host "    $criticalIcon " -NoNewline -ForegroundColor Cyan
    Write-Host "Info:                " -NoNewline -ForegroundColor Gray
    Write-Host ("{0,5:N0}" -f $infoCount) -NoNewline -ForegroundColor Cyan
    Write-Host "  (For awareness)" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host $separator -ForegroundColor DarkGray
    Write-Host ""

    # Issue breakdown
    Write-Host "    Issue Breakdown" -ForegroundColor White
    Write-Host "    ───────────────────────" -ForegroundColor DarkGray

    # Group issues by type
    $issueGroups = $ScanResults.Issues | Group-Object -Property Issue | Sort-Object Count -Descending

    $treeIndex = 0
    foreach ($group in $issueGroups) {
        $treeIndex++
        $isLast = $treeIndex -eq $issueGroups.Count
        $connector = if ($isLast) { "`u{2514}" } else { "`u{251C}" }

        $issue = $group.Name
        $count = $group.Count
        $severity = ($group.Group | Select-Object -First 1).Severity

        $severityIcon = switch ($severity) {
            'Critical' { [char]0x25CF; 'Red' }
            'Warning' { [char]0x25CF; 'Yellow' }
            'Info' { [char]0x25CF; 'Cyan' }
            default { [char]0x25CB; 'Gray' }
        }

        $displayName = switch ($issue) {
            'PathTooLong' { 'Path too long' }
            'PathNearLimit' { 'Path near limit' }
            'FileNameTooLong' { 'File name too long' }
            'InvalidCharacters' { 'Invalid characters' }
            'ReservedName' { 'Reserved names' }
            'BlockedFileType' { 'Blocked file types' }
            'ProblematicFile' { 'Problematic files' }
            'ProblematicFolder' { 'Problematic folders' }
            'FileTooLarge' { 'File too large' }
            'LargeFile' { 'Large files' }
            'NameConflict' { 'Name conflicts' }
            'HiddenItem' { 'Hidden items' }
            'SystemFile' { 'System files' }
            'EmptyFolder' { 'Empty folders' }
            default { $issue }
        }

        Write-Host "    $connector── " -NoNewline -ForegroundColor DarkGray
        Write-Host $displayName.PadRight(22) -NoNewline -ForegroundColor Gray
        Write-Host ("{0,5:N0}" -f $count) -NoNewline -ForegroundColor White
        Write-Host "  " -NoNewline
        Write-Host $severityIcon[0] -ForegroundColor $severityIcon[1]
    }

    Write-Host ""
}

function Write-ReportPaths {
    <#
    .SYNOPSIS
        Displays the paths to generated report files.

    .PARAMETER ReportPaths
        Hashtable of report format to file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ReportPaths
    )

    $separator = "  " + ("=" * 60)

    Write-Host $separator -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    Reports Generated" -ForegroundColor White
    Write-Host "    ───────────────────────" -ForegroundColor DarkGray

    $reportIndex = 0
    $reportCount = $ReportPaths.Count

    foreach ($format in $ReportPaths.Keys | Sort-Object) {
        $reportIndex++
        $isLast = $reportIndex -eq $reportCount
        $connector = if ($isLast) { "`u{2514}" } else { "`u{251C}" }

        $path = $ReportPaths[$format]

        Write-Host "    $connector── " -NoNewline -ForegroundColor DarkGray
        Write-Host "${format}: " -NoNewline -ForegroundColor Cyan
        Write-Host $path -ForegroundColor White
    }

    Write-Host ""
    Write-Host "    Tip: " -NoNewline -ForegroundColor DarkGray
    Write-Host "Open the HTML report for interactive filtering and search" -ForegroundColor Gray
    Write-Host ""
    Write-Host $separator -ForegroundColor DarkGray
    Write-Host ""
}

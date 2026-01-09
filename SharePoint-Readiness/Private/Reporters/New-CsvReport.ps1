function New-CsvReport {
    <#
    .SYNOPSIS
        Generates a CSV report from scan results.

    .DESCRIPTION
        Creates a CSV file with all issues, suitable for Excel analysis
        and client remediation tracking.

    .PARAMETER ScanResults
        The scan results object from Test-SPReadiness.

    .PARAMETER OutputPath
        The path for the output CSV file.

    .PARAMETER IncludeMetadata
        If true, includes scan metadata columns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ScanResults,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$IncludeMetadata
    )

    # Build CSV rows
    $csvRows = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($issue in $ScanResults.Issues) {
        $row = [PSCustomObject]@{
            Severity = $issue.Severity
            IssueType = $issue.Issue
            Category = if ($issue.Category) { $issue.Category } else { 'Other' }
            ItemPath = $issue.Path
            ItemName = $issue.Name
            ItemType = $issue.Type
            Description = $issue.IssueDescription
            Suggestion = $issue.Suggestion
        }

        # Add issue-specific details
        if ($issue.FileSize) {
            $row | Add-Member -NotePropertyName 'FileSize' -NotePropertyValue $issue.FileSize
            $row | Add-Member -NotePropertyName 'FileSizeFormatted' -NotePropertyValue (Format-FileSize -Bytes $issue.FileSize)
        }

        if ($issue.CurrentValue) {
            $row | Add-Member -NotePropertyName 'CurrentValue' -NotePropertyValue $issue.CurrentValue
        }

        if ($issue.Limit) {
            $row | Add-Member -NotePropertyName 'Limit' -NotePropertyValue $issue.Limit
        }

        if ($issue.AvailableChars) {
            $row | Add-Member -NotePropertyName 'AvailableChars' -NotePropertyValue $issue.AvailableChars
        }

        if ($issue.FileExtension) {
            $row | Add-Member -NotePropertyName 'FileExtension' -NotePropertyValue $issue.FileExtension
        }

        if ($issue.ConflictsWith) {
            $conflictPaths = if ($issue.ConflictsWith -is [array]) {
                $issue.ConflictsWith -join '; '
            } else {
                $issue.ConflictsWith
            }
            $row | Add-Member -NotePropertyName 'ConflictsWith' -NotePropertyValue $conflictPaths
        }

        if ($issue.SuggestedName) {
            $row | Add-Member -NotePropertyName 'SuggestedName' -NotePropertyValue $issue.SuggestedName
        }

        # Add metadata if requested
        if ($IncludeMetadata) {
            $row | Add-Member -NotePropertyName 'SourceRoot' -NotePropertyValue $ScanResults.SourcePath
            $row | Add-Member -NotePropertyName 'DestinationUrl' -NotePropertyValue $ScanResults.DestinationUrl
            $row | Add-Member -NotePropertyName 'ScanDate' -NotePropertyValue $ScanResults.ScanDate.ToString("yyyy-MM-dd HH:mm:ss")
        }

        $csvRows.Add($row)
    }

    # Sort by severity (Critical first) then by path
    $severityOrder = @{ 'Critical' = 1; 'Warning' = 2; 'Info' = 3 }
    $sortedRows = $csvRows | Sort-Object @{
        Expression = { $severityOrder[$_.Severity] }
    }, ItemPath

    # Export to CSV
    $sortedRows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

    Write-Verbose "CSV report generated: $OutputPath"
}

function New-RemediationCsv {
    <#
    .SYNOPSIS
        Generates a simplified CSV for client remediation tracking.

    .DESCRIPTION
        Creates a CSV focused on actionable items with checkboxes for
        tracking remediation progress.

    .PARAMETER ScanResults
        The scan results object.

    .PARAMETER OutputPath
        Output file path.

    .PARAMETER CriticalOnly
        If true, only include critical issues.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ScanResults,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$CriticalOnly
    )

    $issues = $ScanResults.Issues
    if ($CriticalOnly) {
        $issues = $issues | Where-Object { $_.Severity -eq 'Critical' }
    }

    $rows = foreach ($issue in $issues) {
        [PSCustomObject]@{
            'Status' = '[ ]'  # Checkbox for tracking
            'Priority' = $issue.Severity
            'Issue' = $issue.IssueDescription
            'Location' = $issue.Path
            'Fix Required' = $issue.Suggestion
            'Assigned To' = ''
            'Notes' = ''
        }
    }

    $rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

    Write-Verbose "Remediation CSV generated: $OutputPath"
}

function New-JsonReport {
    <#
    .SYNOPSIS
        Generates a JSON report from scan results.

    .DESCRIPTION
        Creates a structured JSON file suitable for programmatic
        access and integration with other tools.

    .PARAMETER ScanResults
        The scan results object from Test-SPReadiness.

    .PARAMETER OutputPath
        The path for the output JSON file.

    .PARAMETER Compress
        If true, outputs minified JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ScanResults,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$Compress
    )

    # Calculate statistics
    $criticalCount = ($ScanResults.Issues | Where-Object { $_.Severity -eq 'Critical' }).Count
    $warningCount = ($ScanResults.Issues | Where-Object { $_.Severity -eq 'Warning' }).Count
    $infoCount = ($ScanResults.Issues | Where-Object { $_.Severity -eq 'Info' }).Count

    # Calculate readiness score
    $criticalDeduction = [Math]::Min(50, $criticalCount * 2)
    $warningDeduction = [Math]::Min(25, $warningCount * 0.5)
    $readinessScore = [Math]::Max(0, 100 - $criticalDeduction - $warningDeduction)

    # Group issues by category
    $issuesByCategory = @{}
    $ScanResults.Issues | Group-Object -Property { if ($_.Category) { $_.Category } else { 'Other' } } | ForEach-Object {
        $issuesByCategory[$_.Name] = $_.Count
    }

    # Group issues by type
    $issuesByType = @{}
    $ScanResults.Issues | Group-Object -Property Issue | ForEach-Object {
        $issuesByType[$_.Name] = $_.Count
    }

    # Build structured report
    $report = [ordered]@{
        reportInfo = [ordered]@{
            generatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            generatorVersion = "1.0.0"
            reportFormat = "SharePoint-Readiness-v1"
        }

        scanInfo = [ordered]@{
            sourcePath = $ScanResults.SourcePath
            destinationUrl = $ScanResults.DestinationUrl
            destinationPathLength = $ScanResults.DestinationPathLength
            availablePathChars = $ScanResults.AvailablePathChars
            scanDate = $ScanResults.ScanDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
            durationSeconds = [Math]::Round($ScanResults.Duration.TotalSeconds, 2)
            totalItems = $ScanResults.TotalItems
            totalSizeBytes = $ScanResults.TotalSize
            totalSizeFormatted = Format-FileSize -Bytes $ScanResults.TotalSize
        }

        summary = [ordered]@{
            readinessScore = [int]$readinessScore
            totalIssues = $ScanResults.Issues.Count
            criticalCount = $criticalCount
            warningCount = $warningCount
            infoCount = $infoCount
            issuesByCategory = $issuesByCategory
            issuesByType = $issuesByType
        }

        issues = @(
            foreach ($issue in $ScanResults.Issues) {
                $issueObj = [ordered]@{
                    severity = $issue.Severity
                    issueType = $issue.Issue
                    category = if ($issue.Category) { $issue.Category } else { 'Other' }
                    path = $issue.Path
                    name = $issue.Name
                    itemType = $issue.Type
                    description = $issue.IssueDescription
                    suggestion = $issue.Suggestion
                }

                # Add optional fields if present
                if ($null -ne $issue.FileSize) {
                    $issueObj['fileSizeBytes'] = $issue.FileSize
                }
                if ($null -ne $issue.CurrentValue) {
                    $issueObj['currentValue'] = $issue.CurrentValue
                }
                if ($null -ne $issue.Limit) {
                    $issueObj['limit'] = $issue.Limit
                }
                if ($null -ne $issue.AvailableChars) {
                    $issueObj['availableChars'] = $issue.AvailableChars
                }
                if ($issue.FileExtension) {
                    $issueObj['fileExtension'] = $issue.FileExtension
                }
                if ($issue.SuggestedName) {
                    $issueObj['suggestedName'] = $issue.SuggestedName
                }
                if ($issue.ConflictsWith) {
                    $issueObj['conflictsWith'] = $issue.ConflictsWith
                }
                if ($issue.InvalidChars) {
                    $issueObj['invalidCharacters'] = $issue.InvalidChars
                }

                $issueObj
            }
        )

        settings = [ordered]@{
            warningThreshold = $ScanResults.Settings.WarningThreshold
            maxPathLength = 400
            maxFileSize = "250 GB"
        }
    }

    # Add enumeration errors if any
    if ($ScanResults.EnumerationErrors -and $ScanResults.EnumerationErrors.Count -gt 0) {
        $report['enumerationErrors'] = @(
            foreach ($error in $ScanResults.EnumerationErrors) {
                [ordered]@{
                    path = $error.Path
                    error = $error.Error
                }
            }
        )
    }

    # Convert to JSON
    $depth = 10
    if ($Compress) {
        $json = $report | ConvertTo-Json -Depth $depth -Compress
    }
    else {
        $json = $report | ConvertTo-Json -Depth $depth
    }

    # Write file
    $json | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

    Write-Verbose "JSON report generated: $OutputPath"
}

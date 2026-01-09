function New-HtmlReport {
    <#
    .SYNOPSIS
        Generates an interactive HTML report from scan results.

    .DESCRIPTION
        Creates a professional HTML report with:
        - Executive summary with readiness score
        - Interactive issue table with filtering and sorting
        - Issue details with remediation suggestions
        - Dark/light mode support

    .PARAMETER ScanResults
        The scan results object from Test-SPReadiness.

    .PARAMETER OutputPath
        The path for the output HTML file.

    .PARAMETER Title
        Custom report title.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ScanResults,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [string]$Title = "SharePoint Migration Readiness Report"
    )

    # Calculate statistics
    $totalItems = $ScanResults.TotalItems
    $criticalCount = ($ScanResults.Issues | Where-Object { $_.Severity -eq 'Critical' }).Count
    $warningCount = ($ScanResults.Issues | Where-Object { $_.Severity -eq 'Warning' }).Count
    $infoCount = ($ScanResults.Issues | Where-Object { $_.Severity -eq 'Info' }).Count
    $totalIssues = $ScanResults.Issues.Count

    # Calculate readiness score
    $criticalDeduction = [Math]::Min(50, $criticalCount * 2)
    $warningDeduction = [Math]::Min(25, $warningCount * 0.5)
    $readinessScore = [Math]::Max(0, 100 - $criticalDeduction - $warningDeduction)
    $readinessScore = [Math]::Round($readinessScore)

    # Format values
    $totalSizeFormatted = Format-FileSize -Bytes $ScanResults.TotalSize
    $scanDate = $ScanResults.ScanDate.ToString("yyyy-MM-dd HH:mm:ss")
    $duration = $ScanResults.Duration.ToString("mm\:ss")

    # Score color class
    $scoreClass = if ($readinessScore -ge 90) { 'score-good' }
                  elseif ($readinessScore -ge 70) { 'score-warning' }
                  elseif ($readinessScore -ge 50) { 'score-caution' }
                  else { 'score-critical' }

    # Build issue rows
    $issueRows = ""
    $issueIndex = 0
    foreach ($issue in $ScanResults.Issues | Select-Object -First 1000) {
        $issueIndex++
        $severityClass = $issue.Severity.ToLower()
        $escapedPath = [System.Web.HttpUtility]::HtmlEncode($issue.Path)
        $escapedName = [System.Web.HttpUtility]::HtmlEncode($issue.Name)
        $escapedDesc = [System.Web.HttpUtility]::HtmlEncode($issue.IssueDescription)
        $escapedSuggestion = [System.Web.HttpUtility]::HtmlEncode($issue.Suggestion)
        $category = if ($issue.Category) { $issue.Category } else { 'Other' }

        $issueRows += @"
        <tr class="severity-$severityClass" data-severity="$($issue.Severity)" data-category="$category">
            <td><span class="severity-badge $severityClass">$($issue.Severity)</span></td>
            <td class="issue-type">$($issue.Issue)</td>
            <td class="item-name" title="$escapedPath">$escapedName</td>
            <td class="description">$escapedDesc</td>
            <td class="suggestion">$escapedSuggestion</td>
        </tr>
"@
    }

    # Build category summary
    $categoryGroups = $ScanResults.Issues | Group-Object -Property { if ($_.Category) { $_.Category } else { 'Other' } } | Sort-Object Count -Descending
    $categorySummary = ""
    foreach ($group in $categoryGroups) {
        $categorySummary += "<div class='category-item'><span class='category-name'>$($group.Name)</span><span class='category-count'>$($group.Count)</span></div>"
    }

    # Generate HTML
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$Title</title>
    <style>
        :root {
            --bg-primary: #1a1a2e;
            --bg-secondary: #16213e;
            --bg-card: #0f3460;
            --text-primary: #eaeaea;
            --text-secondary: #a0a0a0;
            --accent: #e94560;
            --success: #00d26a;
            --warning: #ffc107;
            --info: #17a2b8;
            --critical: #dc3545;
            --border: #2a2a4a;
        }

        .light-mode {
            --bg-primary: #f5f5f5;
            --bg-secondary: #ffffff;
            --bg-card: #ffffff;
            --text-primary: #333333;
            --text-secondary: #666666;
            --border: #e0e0e0;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
            padding: 20px;
        }

        .container { max-width: 1400px; margin: 0 auto; }

        .header {
            text-align: center;
            padding: 40px 20px;
            background: linear-gradient(135deg, var(--bg-secondary), var(--bg-card));
            border-radius: 12px;
            margin-bottom: 30px;
        }

        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header .subtitle { color: var(--text-secondary); font-size: 1.1em; }

        .theme-toggle {
            position: absolute;
            top: 20px;
            right: 20px;
            background: var(--bg-card);
            border: 1px solid var(--border);
            color: var(--text-primary);
            padding: 8px 16px;
            border-radius: 20px;
            cursor: pointer;
        }

        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .card {
            background: var(--bg-card);
            border-radius: 12px;
            padding: 24px;
            border: 1px solid var(--border);
        }

        .card h3 {
            color: var(--text-secondary);
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 15px;
        }

        .score-display {
            text-align: center;
            padding: 20px;
        }

        .score-value {
            font-size: 4em;
            font-weight: bold;
        }

        .score-good { color: var(--success); }
        .score-warning { color: var(--warning); }
        .score-caution { color: #fd7e14; }
        .score-critical { color: var(--critical); }

        .score-bar {
            height: 8px;
            background: var(--border);
            border-radius: 4px;
            margin-top: 15px;
            overflow: hidden;
        }

        .score-fill {
            height: 100%;
            border-radius: 4px;
            transition: width 0.5s ease;
        }

        .stat-row {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            border-bottom: 1px solid var(--border);
        }

        .stat-row:last-child { border-bottom: none; }
        .stat-label { color: var(--text-secondary); }
        .stat-value { font-weight: 600; }

        .severity-counts {
            display: flex;
            gap: 20px;
            justify-content: center;
            flex-wrap: wrap;
        }

        .severity-item {
            text-align: center;
            padding: 15px 25px;
            border-radius: 8px;
            background: var(--bg-secondary);
        }

        .severity-item.critical { border-left: 4px solid var(--critical); }
        .severity-item.warning { border-left: 4px solid var(--warning); }
        .severity-item.info { border-left: 4px solid var(--info); }

        .severity-count {
            font-size: 2em;
            font-weight: bold;
            display: block;
        }

        .severity-label {
            color: var(--text-secondary);
            font-size: 0.85em;
        }

        .category-item {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid var(--border);
        }

        .filter-bar {
            background: var(--bg-card);
            padding: 20px;
            border-radius: 12px;
            margin-bottom: 20px;
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
            align-items: center;
        }

        .filter-bar input, .filter-bar select {
            background: var(--bg-secondary);
            border: 1px solid var(--border);
            color: var(--text-primary);
            padding: 10px 15px;
            border-radius: 6px;
            font-size: 14px;
        }

        .filter-bar input { flex: 1; min-width: 200px; }

        table {
            width: 100%;
            border-collapse: collapse;
            background: var(--bg-card);
            border-radius: 12px;
            overflow: hidden;
        }

        th, td {
            padding: 14px 16px;
            text-align: left;
            border-bottom: 1px solid var(--border);
        }

        th {
            background: var(--bg-secondary);
            font-weight: 600;
            color: var(--text-secondary);
            text-transform: uppercase;
            font-size: 0.8em;
            letter-spacing: 0.5px;
            cursor: pointer;
        }

        th:hover { background: var(--bg-card); }

        tr:hover { background: var(--bg-secondary); }

        .severity-badge {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.75em;
            font-weight: 600;
            text-transform: uppercase;
        }

        .severity-badge.critical { background: var(--critical); color: white; }
        .severity-badge.warning { background: var(--warning); color: #333; }
        .severity-badge.info { background: var(--info); color: white; }

        .item-name {
            max-width: 200px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }

        .description { max-width: 300px; }
        .suggestion { max-width: 300px; color: var(--text-secondary); font-size: 0.9em; }

        .footer {
            text-align: center;
            padding: 30px;
            color: var(--text-secondary);
            font-size: 0.85em;
        }

        @media (max-width: 768px) {
            .summary-grid { grid-template-columns: 1fr; }
            .header h1 { font-size: 1.8em; }
            table { font-size: 0.85em; }
            th, td { padding: 10px; }
        }

        @media print {
            body { background: white; color: black; }
            .theme-toggle, .filter-bar { display: none; }
            .card { break-inside: avoid; }
        }
    </style>
</head>
<body>
    <button class="theme-toggle" onclick="toggleTheme()">Toggle Theme</button>

    <div class="container">
        <div class="header">
            <h1>SharePoint Migration Readiness Report</h1>
            <p class="subtitle">Generated on $scanDate</p>
        </div>

        <div class="summary-grid">
            <div class="card score-display">
                <h3>Readiness Score</h3>
                <div class="score-value $scoreClass">$readinessScore%</div>
                <div class="score-bar">
                    <div class="score-fill $scoreClass" style="width: $readinessScore%; background: currentColor;"></div>
                </div>
            </div>

            <div class="card">
                <h3>Scan Summary</h3>
                <div class="stat-row">
                    <span class="stat-label">Source Path</span>
                    <span class="stat-value" title="$($ScanResults.SourcePath)">$(Split-Path $ScanResults.SourcePath -Leaf)</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Total Items</span>
                    <span class="stat-value">$("{0:N0}" -f $totalItems)</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Total Size</span>
                    <span class="stat-value">$totalSizeFormatted</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Scan Duration</span>
                    <span class="stat-value">$duration</span>
                </div>
            </div>

            <div class="card">
                <h3>Issues by Severity</h3>
                <div class="severity-counts">
                    <div class="severity-item critical">
                        <span class="severity-count">$criticalCount</span>
                        <span class="severity-label">Critical</span>
                    </div>
                    <div class="severity-item warning">
                        <span class="severity-count">$warningCount</span>
                        <span class="severity-label">Warning</span>
                    </div>
                    <div class="severity-item info">
                        <span class="severity-count">$infoCount</span>
                        <span class="severity-label">Info</span>
                    </div>
                </div>
            </div>

            <div class="card">
                <h3>Issues by Category</h3>
                $categorySummary
            </div>
        </div>

        <div class="filter-bar">
            <input type="text" id="searchInput" placeholder="Search issues..." onkeyup="filterTable()">
            <select id="severityFilter" onchange="filterTable()">
                <option value="">All Severities</option>
                <option value="Critical">Critical</option>
                <option value="Warning">Warning</option>
                <option value="Info">Info</option>
            </select>
            <span style="color: var(--text-secondary);">Showing <span id="visibleCount">$totalIssues</span> of $totalIssues issues</span>
        </div>

        <table id="issueTable">
            <thead>
                <tr>
                    <th onclick="sortTable(0)">Severity</th>
                    <th onclick="sortTable(1)">Issue Type</th>
                    <th onclick="sortTable(2)">Item Name</th>
                    <th onclick="sortTable(3)">Description</th>
                    <th onclick="sortTable(4)">Suggestion</th>
                </tr>
            </thead>
            <tbody>
                $issueRows
            </tbody>
        </table>

        <div class="footer">
            <p>Generated by SharePoint-Readiness Scanner v1.0.0</p>
            <p>Path available: $($ScanResults.AvailablePathChars) characters | Destination: $($ScanResults.DestinationUrl)</p>
        </div>
    </div>

    <script>
        function toggleTheme() {
            document.body.classList.toggle('light-mode');
        }

        function filterTable() {
            const search = document.getElementById('searchInput').value.toLowerCase();
            const severity = document.getElementById('severityFilter').value;
            const rows = document.querySelectorAll('#issueTable tbody tr');
            let visible = 0;

            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                const rowSeverity = row.dataset.severity;
                const matchSearch = text.includes(search);
                const matchSeverity = !severity || rowSeverity === severity;

                if (matchSearch && matchSeverity) {
                    row.style.display = '';
                    visible++;
                } else {
                    row.style.display = 'none';
                }
            });

            document.getElementById('visibleCount').textContent = visible;
        }

        function sortTable(col) {
            const table = document.getElementById('issueTable');
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));

            const sorted = rows.sort((a, b) => {
                const aVal = a.cells[col].textContent;
                const bVal = b.cells[col].textContent;
                return aVal.localeCompare(bVal);
            });

            sorted.forEach(row => tbody.appendChild(row));
        }
    </script>
</body>
</html>
"@

    # Write file
    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

    Write-Verbose "HTML report generated: $OutputPath"
}

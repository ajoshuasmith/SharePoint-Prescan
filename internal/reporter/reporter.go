package reporter

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/ajoshuasmith/sharepoint-prescan/internal/models"
)

// Reporter generates reports from scan results
type Reporter struct {
	outputDir string
}

// NewReporter creates a new Reporter instance
func NewReporter(outputDir string) *Reporter {
	return &Reporter{
		outputDir: outputDir,
	}
}

// GenerateJSON creates a JSON report file
func (r *Reporter) GenerateJSON(result *models.ScanResult, filename string) error {
	if filename == "" {
		filename = fmt.Sprintf("sp-readiness-%s.json", time.Now().Format("20060102-150405"))
	}

	outputPath := filepath.Join(r.outputDir, filename)

	file, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create JSON file: %w", err)
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")

	if err := encoder.Encode(result); err != nil {
		return fmt.Errorf("failed to encode JSON: %w", err)
	}

	fmt.Printf("JSON report saved: %s\n", outputPath)
	return nil
}

// GenerateCSV creates a CSV report file
func (r *Reporter) GenerateCSV(result *models.ScanResult, filename string) error {
	if filename == "" {
		filename = fmt.Sprintf("sp-readiness-%s.csv", time.Now().Format("20060102-150405"))
	}

	outputPath := filepath.Join(r.outputDir, filename)

	file, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create CSV file: %w", err)
	}
	defer file.Close()

	writer := csv.NewWriter(file)
	defer writer.Flush()

	// Write header
	header := []string{
		"Path",
		"Type",
		"Severity",
		"Message",
		"Details",
		"Category",
		"Size",
		"IsDirectory",
		"RemediationHint",
	}
	if err := writer.Write(header); err != nil {
		return fmt.Errorf("failed to write CSV header: %w", err)
	}

	// Sort issues by severity and type
	sortedIssues := make([]models.Issue, len(result.Issues))
	copy(sortedIssues, result.Issues)
	sort.Slice(sortedIssues, func(i, j int) bool {
		if sortedIssues[i].Severity != sortedIssues[j].Severity {
			return severityRank(sortedIssues[i].Severity) < severityRank(sortedIssues[j].Severity)
		}
		return sortedIssues[i].Path < sortedIssues[j].Path
	})

	// Write data rows
	for _, issue := range sortedIssues {
		row := []string{
			issue.Path,
			string(issue.Type),
			string(issue.Severity),
			issue.Message,
			issue.Details,
			issue.Category,
			formatBytes(issue.Size),
			formatBool(issue.IsDirectory),
			issue.RemediationHint,
		}
		if err := writer.Write(row); err != nil {
			return fmt.Errorf("failed to write CSV row: %w", err)
		}
	}

	fmt.Printf("CSV report saved: %s\n", outputPath)
	return nil
}

// GenerateHTML creates an HTML report file
func (r *Reporter) GenerateHTML(result *models.ScanResult, filename string) error {
	if filename == "" {
		filename = fmt.Sprintf("sp-readiness-%s.html", time.Now().Format("20060102-150405"))
	}

	outputPath := filepath.Join(r.outputDir, filename)

	file, err := os.Create(outputPath)
	if err != nil {
		return fmt.Errorf("failed to create HTML file: %w", err)
	}
	defer file.Close()

	html := generateHTMLContent(result)
	if _, err := file.WriteString(html); err != nil {
		return fmt.Errorf("failed to write HTML content: %w", err)
	}

	fmt.Printf("HTML report saved: %s\n", outputPath)
	return nil
}

func severityRank(severity models.Severity) int {
	switch severity {
	case models.SeverityCritical:
		return 0
	case models.SeverityWarning:
		return 1
	case models.SeverityInfo:
		return 2
	default:
		return 3
	}
}

func formatBytes(bytes int64) string {
	if bytes == 0 {
		return ""
	}

	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}

	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}

	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

func formatBool(b bool) string {
	if b {
		return "Yes"
	}
	return "No"
}

func formatDuration(d time.Duration) string {
	if d < time.Second {
		return fmt.Sprintf("%dms", d.Milliseconds())
	}
	if d < time.Minute {
		return fmt.Sprintf("%.1fs", d.Seconds())
	}
	if d < time.Hour {
		return fmt.Sprintf("%.1fm", d.Minutes())
	}
	return fmt.Sprintf("%.1fh", d.Hours())
}

func generateHTMLContent(result *models.ScanResult) string {
	// Sort issues by severity
	sortedIssues := make([]models.Issue, len(result.Issues))
	copy(sortedIssues, result.Issues)
	sort.Slice(sortedIssues, func(i, j int) bool {
		if sortedIssues[i].Severity != sortedIssues[j].Severity {
			return severityRank(sortedIssues[i].Severity) < severityRank(sortedIssues[j].Severity)
		}
		return sortedIssues[i].Path < sortedIssues[j].Path
	})

	html := `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SharePoint Readiness Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; margin-bottom: 10px; font-size: 32px; }
        h2 { color: #333; margin: 30px 0 15px 0; font-size: 24px; border-bottom: 2px solid #0078d4; padding-bottom: 8px; }
        h3 { color: #555; margin: 20px 0 10px 0; font-size: 18px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
        .summary-card { background: #f9f9f9; padding: 20px; border-radius: 6px; border-left: 4px solid #0078d4; }
        .summary-card h3 { margin: 0 0 10px 0; font-size: 14px; color: #666; text-transform: uppercase; }
        .summary-card .value { font-size: 28px; font-weight: bold; color: #333; }
        .severity-summary { display: flex; gap: 20px; margin: 20px 0; flex-wrap: wrap; }
        .severity-card { flex: 1; min-width: 150px; padding: 15px; border-radius: 6px; color: white; text-align: center; }
        .severity-card.critical { background: #d13438; }
        .severity-card.warning { background: #ff8c00; }
        .severity-card.info { background: #0078d4; }
        .severity-card .count { font-size: 32px; font-weight: bold; display: block; }
        .severity-card .label { font-size: 14px; text-transform: uppercase; opacity: 0.9; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #0078d4; color: white; font-weight: 600; position: sticky; top: 0; }
        tr:hover { background: #f9f9f9; }
        .severity-badge { display: inline-block; padding: 4px 12px; border-radius: 4px; font-size: 12px; font-weight: 600; text-transform: uppercase; }
        .severity-badge.critical { background: #d13438; color: white; }
        .severity-badge.warning { background: #ff8c00; color: white; }
        .severity-badge.info { background: #0078d4; color: white; }
        .path { font-family: 'Consolas', 'Courier New', monospace; font-size: 12px; word-break: break-all; }
        .filter-bar { margin: 20px 0; padding: 15px; background: #f9f9f9; border-radius: 6px; display: flex; gap: 15px; flex-wrap: wrap; align-items: center; }
        .filter-bar input { padding: 8px 12px; border: 1px solid #ddd; border-radius: 4px; flex: 1; min-width: 200px; }
        .filter-bar select { padding: 8px 12px; border: 1px solid #ddd; border-radius: 4px; background: white; }
        .timestamp { color: #666; font-size: 14px; margin-bottom: 20px; }
        @media print { .filter-bar { display: none; } }
    </style>
</head>
<body>
    <div class="container">
        <h1>SharePoint Readiness Report</h1>
        <div class="timestamp">Generated: ` + result.EndTime.Format("2006-01-02 15:04:05") + `</div>

        <h2>Scan Summary</h2>
        <div class="summary">
            <div class="summary-card">
                <h3>Scan Path</h3>
                <div class="value" style="font-size: 16px;">` + result.ScanPath + `</div>
            </div>
            <div class="summary-card">
                <h3>Total Items</h3>
                <div class="value">` + fmt.Sprintf("%d", result.TotalItems) + `</div>
            </div>
            <div class="summary-card">
                <h3>Files</h3>
                <div class="value">` + fmt.Sprintf("%d", result.TotalFiles) + `</div>
            </div>
            <div class="summary-card">
                <h3>Folders</h3>
                <div class="value">` + fmt.Sprintf("%d", result.TotalFolders) + `</div>
            </div>
            <div class="summary-card">
                <h3>Total Size</h3>
                <div class="value" style="font-size: 20px;">` + formatBytes(result.TotalSize) + `</div>
            </div>
            <div class="summary-card">
                <h3>Scan Duration</h3>
                <div class="value" style="font-size: 20px;">` + formatDuration(result.Duration) + `</div>
            </div>
        </div>

        <h2>Issues Found: ` + fmt.Sprintf("%d", result.IssuesFound) + `</h2>
        <div class="severity-summary">
            <div class="severity-card critical">
                <span class="count">` + fmt.Sprintf("%d", result.Summary.BySeverity[models.SeverityCritical]) + `</span>
                <span class="label">Critical</span>
            </div>
            <div class="severity-card warning">
                <span class="count">` + fmt.Sprintf("%d", result.Summary.BySeverity[models.SeverityWarning]) + `</span>
                <span class="label">Warning</span>
            </div>
            <div class="severity-card info">
                <span class="count">` + fmt.Sprintf("%d", result.Summary.BySeverity[models.SeverityInfo]) + `</span>
                <span class="label">Info</span>
            </div>
        </div>

        <h2>Issues by Type</h2>
        <div class="summary">
`

	// Add issue type summary
	for issueType, count := range result.Summary.ByType {
		html += `            <div class="summary-card">
                <h3>` + string(issueType) + `</h3>
                <div class="value">` + fmt.Sprintf("%d", count) + `</div>
            </div>
`
	}

	html += `        </div>

        <h2>Issue Details</h2>
        <div class="filter-bar">
            <input type="text" id="searchBox" placeholder="Search paths..." onkeyup="filterTable()">
            <select id="severityFilter" onchange="filterTable()">
                <option value="">All Severities</option>
                <option value="Critical">Critical</option>
                <option value="Warning">Warning</option>
                <option value="Info">Info</option>
            </select>
            <select id="typeFilter" onchange="filterTable()">
                <option value="">All Types</option>
`

	// Add unique issue types to filter
	typeSet := make(map[models.IssueType]bool)
	for _, issue := range sortedIssues {
		typeSet[issue.Type] = true
	}
	for issueType := range typeSet {
		html += `                <option value="` + string(issueType) + `">` + string(issueType) + `</option>
`
	}

	html += `            </select>
        </div>

        <table id="issuesTable">
            <thead>
                <tr>
                    <th>Severity</th>
                    <th>Type</th>
                    <th>Path</th>
                    <th>Message</th>
                    <th>Details</th>
                </tr>
            </thead>
            <tbody>
`

	// Add issue rows
	for _, issue := range sortedIssues {
		severityClass := string(issue.Severity)
		severityClass = severityClass[:1] + string(severityClass[1:])[:]
		html += `                <tr>
                    <td><span class="severity-badge ` + string(issue.Severity) + `">` + string(issue.Severity) + `</span></td>
                    <td>` + string(issue.Type) + `</td>
                    <td class="path">` + issue.Path + `</td>
                    <td>` + issue.Message + `</td>
                    <td>` + issue.Details
		if issue.RemediationHint != "" {
			html += `<br><small><strong>Fix:</strong> ` + issue.RemediationHint + `</small>`
		}
		html += `</td>
                </tr>
`
	}

	html += `            </tbody>
        </table>
    </div>

    <script>
        function filterTable() {
            const searchValue = document.getElementById('searchBox').value.toLowerCase();
            const severityFilter = document.getElementById('severityFilter').value;
            const typeFilter = document.getElementById('typeFilter').value;
            const table = document.getElementById('issuesTable');
            const rows = table.getElementsByTagName('tr');

            for (let i = 1; i < rows.length; i++) {
                const row = rows[i];
                const severity = row.cells[0].textContent.trim();
                const type = row.cells[1].textContent;
                const path = row.cells[2].textContent.toLowerCase();

                let showRow = true;

                if (searchValue && !path.includes(searchValue)) {
                    showRow = false;
                }

                if (severityFilter && severity !== severityFilter) {
                    showRow = false;
                }

                if (typeFilter && type !== typeFilter) {
                    showRow = false;
                }

                row.style.display = showRow ? '' : 'none';
            }
        }
    </script>
</body>
</html>`

	return html
}

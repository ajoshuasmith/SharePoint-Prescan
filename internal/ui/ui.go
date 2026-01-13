package ui

import (
	"fmt"
	"strings"
	"time"

	"github.com/ajoshuasmith/sharepoint-prescan/internal/models"
)

// ShowBanner displays the application banner
func ShowBanner() {
	banner := `
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   ███████╗██████╗ ██████╗ ███████╗ █████╗ ██████╗ ██╗   ██╗  ║
║   ██╔════╝██╔══██╗██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝  ║
║   ███████╗██████╔╝██████╔╝█████╗  ███████║██║  ██║ ╚████╔╝   ║
║   ╚════██║██╔═══╝ ██╔══██╗██╔══╝  ██╔══██║██║  ██║  ╚██╔╝    ║
║   ███████║██║     ██║  ██║███████╗██║  ██║██████╔╝   ██║     ║
║   ╚══════╝╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝    ╚═╝     ║
║                                                               ║
║         SharePoint Online Migration Readiness Scanner        ║
║                     Built for Speed & Scale                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
`
	fmt.Println(banner)
}

// ShowProgress displays scan progress
func ShowProgress(progress *models.ScanProgress, startTime time.Time) {
	elapsed := time.Since(startTime)
	rate := float64(progress.ItemsScanned) / elapsed.Seconds()

	// Calculate display values
	files := formatNumber(progress.FilesScanned)
	dirs := formatNumber(progress.DirsScanned)
	size := formatBytes(progress.BytesScanned)
	items := formatNumber(progress.ItemsScanned)
	rateStr := formatNumber(int64(rate))
	issues := formatNumber(int64(progress.IssuesFound))

	// Build progress bar
	barWidth := 40
	bar := strings.Repeat("█", barWidth)

	// Truncate path if too long
	currentPath := progress.CurrentPath
	maxPathLen := 60
	if len(currentPath) > maxPathLen {
		currentPath = "..." + currentPath[len(currentPath)-maxPathLen+3:]
	}

	// Clear line and print progress
	fmt.Printf("\r\033[K")
	fmt.Printf("┌─[%s]──────────────────────────────────────────┐\n", formatDuration(elapsed))
	fmt.Printf("│ Items: %s  |  Files: %s  |  Dirs: %s  |  Size: %s\n", items, files, dirs, size)
	fmt.Printf("│ Rate: %s items/sec  |  Issues: %s\n", rateStr, issues)
	fmt.Printf("│ %s\n", bar)
	fmt.Printf("│ Scanning: %s\n", currentPath)
	fmt.Printf("└────────────────────────────────────────────────────────────┘")

	// Move cursor up to redraw on next update
	fmt.Print("\033[5A")
}

// ClearProgress clears the progress display
func ClearProgress() {
	fmt.Print("\r\033[K\033[1B\033[K\033[1B\033[K\033[1B\033[K\033[1B\033[K\033[1B\033[K")
}

// ShowSummary displays the scan summary
func ShowSummary(result *models.ScanResult) {
	fmt.Println("\n╔═══════════════════════════════════════════════════════════════╗")
	fmt.Println("║                        SCAN COMPLETE                          ║")
	fmt.Println("╚═══════════════════════════════════════════════════════════════╝")
	fmt.Println()

	// Scan statistics
	fmt.Printf("📁 Scan Path:      %s\n", result.ScanPath)
	fmt.Printf("⏱️  Duration:       %s\n", formatDuration(result.Duration))
	fmt.Printf("📊 Total Items:    %s (%s files, %s folders)\n",
		formatNumber(result.TotalItems),
		formatNumber(result.TotalFiles),
		formatNumber(result.TotalFolders))
	fmt.Printf("💾 Total Size:     %s\n", formatBytes(result.TotalSize))
	fmt.Printf("⚡ Scan Rate:      %s items/sec\n",
		formatNumber(int64(float64(result.TotalItems)/result.Duration.Seconds())))
	fmt.Println()

	// Issues summary
	if result.IssuesFound == 0 {
		fmt.Println("✅ SUCCESS! No issues found. This path is ready for SharePoint Online migration.")
		return
	}

	fmt.Printf("⚠️  Issues Found:   %s\n", formatNumber(int64(result.IssuesFound)))
	fmt.Println()

	// By severity
	fmt.Println("By Severity:")
	critical := result.Summary.BySeverity[models.SeverityCritical]
	warning := result.Summary.BySeverity[models.SeverityWarning]
	info := result.Summary.BySeverity[models.SeverityInfo]

	if critical > 0 {
		fmt.Printf("  🔴 Critical:  %s (requires immediate action)\n", formatNumber(int64(critical)))
	}
	if warning > 0 {
		fmt.Printf("  🟡 Warning:   %s (recommended to fix)\n", formatNumber(int64(warning)))
	}
	if info > 0 {
		fmt.Printf("  🔵 Info:      %s (review recommended)\n", formatNumber(int64(info)))
	}
	fmt.Println()

	// By type
	fmt.Println("By Issue Type:")
	for issueType, count := range result.Summary.ByType {
		fmt.Printf("  • %-20s %s\n", issueType, formatNumber(int64(count)))
	}
	fmt.Println()

	// Recommendation
	if critical > 0 {
		fmt.Println("⚠️  RECOMMENDATION: Critical issues must be resolved before migration.")
		fmt.Println("    Review the detailed report for remediation steps.")
	} else if warning > 0 {
		fmt.Println("⚠️  RECOMMENDATION: Address warnings to avoid potential issues during migration.")
	} else {
		fmt.Println("✅ RECOMMENDATION: Only informational items found. Review and proceed with migration.")
	}
}

// Helper functions moved to styled.go to avoid duplication

// ShowError displays an error message
func ShowError(msg string, err error) {
	fmt.Printf("\n❌ ERROR: %s\n", msg)
	if err != nil {
		fmt.Printf("   %v\n", err)
	}
}

// ShowWarning displays a warning message
func ShowWarning(msg string) {
	fmt.Printf("\n⚠️  WARNING: %s\n", msg)
}

// ShowInfo displays an info message
func ShowInfo(msg string) {
	fmt.Printf("\nℹ️  %s\n", msg)
}

// ShowSuccess displays a success message
func ShowSuccess(msg string) {
	fmt.Printf("\n✅ %s\n", msg)
}

package ui

import (
	"fmt"
	"strings"
	"time"

	"github.com/ajoshuasmith/sharepoint-prescan/internal/models"
	"github.com/charmbracelet/lipgloss"
)

var lastLineCount = 0

// ShowStyledProgress displays scan progress with the custom UI theme.
func ShowStyledProgress(progress *models.ScanProgress, startTime time.Time) {
	// Clear previous lines
	if lastLineCount > 0 {
		for i := 0; i < lastLineCount; i++ {
			fmt.Print("\033[1A\033[K") // Move up one line and clear it
		}
	}

	elapsed := time.Since(startTime)
	rate := float64(progress.ItemsScanned) / elapsed.Seconds()

	// Build progress display
	var b strings.Builder

	// Header with animated spinner
	spinner := getSpinnerFrame(time.Now())
	header := spinner + "  " + lipgloss.NewStyle().Foreground(accentColor).Render("Scanning in progress...")
	b.WriteString(header + "\n\n")

	// Stats in a styled box
	stats := renderProgressStats(progress, elapsed, rate)
	styledStats := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(borderColor).
		Padding(0, 2).
		Render(stats)

	b.WriteString(styledStats + "\n")

	// Progress bar
	progressBar := renderProgressBar(progress.ItemsScanned, elapsed)
	b.WriteString("\n  " + progressBar + "\n\n")

	// Current path
	if progress.CurrentPath != "" {
		currentPath := progress.CurrentPath
		maxLen := 70
		if len(currentPath) > maxLen {
			currentPath = "..." + currentPath[len(currentPath)-maxLen+3:]
		}

		pathDisplay := subtleStyle.Render("  └─ ") + pathStyle.Render(currentPath)
		b.WriteString(pathDisplay + "\n")
	}

	// Help text
	b.WriteString("\n")
	b.WriteString(subtleStyle.Render("  Press ctrl+c to cancel") + "\n")

	output := b.String()
	fmt.Print(output)

	// Count lines for next clear
	lastLineCount = strings.Count(output, "\n")
}

// ClearStyledProgress clears the progress display
func ClearStyledProgress() {
	if lastLineCount > 0 {
		for i := 0; i < lastLineCount; i++ {
			fmt.Print("\033[1A\033[K")
		}
		lastLineCount = 0
	}
}

func renderProgressStats(stats *models.ScanProgress, elapsed time.Duration, rate float64) string {
	var b strings.Builder

	// Row 1: Basic counts
	b.WriteString(
		statLabelStyle.Render("Items:") + "   " +
		statValueStyle.Render(formatNumber(stats.ItemsScanned)) + "  " +
		subtleStyle.Render("│") + "  " +
		statLabelStyle.Render("Files:") + "   " +
		statValueStyle.Render(formatNumber(stats.FilesScanned)) + "  " +
		subtleStyle.Render("│") + "  " +
		statLabelStyle.Render("Folders:") + " " +
		statValueStyle.Render(formatNumber(stats.DirsScanned)) + "\n",
	)

	// Row 2: Size and performance
	b.WriteString(
		statLabelStyle.Render("Size:") + "    " +
		statValueStyle.Render(formatBytes(stats.BytesScanned)) + "  " +
		subtleStyle.Render("│") + "  " +
		statLabelStyle.Render("Rate:") + "    " +
		statValueStyle.Render(fmt.Sprintf("%s/s", formatNumber(int64(rate)))) + "  " +
		subtleStyle.Render("│") + "  " +
		statLabelStyle.Render("Elapsed:") + " " +
		statValueStyle.Render(formatDuration(elapsed)),
	)

	// Row 3: Issues (if any)
	if stats.IssuesFound > 0 {
		b.WriteString("\n")
		b.WriteString(
			statLabelStyle.Render("Issues:") + "  " +
			warningStyle.Render(formatNumber(int64(stats.IssuesFound))),
		)
	}

	return b.String()
}

func renderProgressBar(itemsScanned int64, elapsed time.Duration) string {
	// Animated indeterminate progress bar
	width := 50
	position := int(elapsed.Milliseconds()/100) % width

	bar := make([]rune, width)
	for i := 0; i < width; i++ {
		bar[i] = '─'
	}

	// Add moving indicator
	gradientSize := 8
	for i := 0; i < gradientSize; i++ {
		pos := (position + i - gradientSize/2 + width) % width
		if pos >= 0 && pos < width {
			switch {
			case i == gradientSize/2:
				bar[pos] = '█'
			case i >= gradientSize/2-1 && i <= gradientSize/2+1:
				bar[pos] = '▓'
			default:
				bar[pos] = '░'
			}
		}
	}

	barStr := string(bar)
	styledBar := lipgloss.NewStyle().Foreground(accentColor).Render(barStr)

	return "  " + styledBar
}

func getSpinnerFrame(t time.Time) string {
	frames := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
	idx := (t.UnixMilli() / 80) % int64(len(frames))
	return lipgloss.NewStyle().Foreground(accentColor).Render(frames[idx])
}

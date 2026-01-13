package ui

import (
	"fmt"
	"strings"
	"time"

	"github.com/ajoshuasmith/sharepoint-prescan/internal/models"
	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Color scheme inspired by Claude Code
var (
	// Primary colors
	primaryColor   = lipgloss.Color("#FF6B35") // Coral orange
	accentColor    = lipgloss.Color("#4ECDC4") // Teal
	successColor   = lipgloss.Color("#95E1D3") // Mint green
	warningColor   = lipgloss.Color("#FFD93D") // Yellow
	errorColor     = lipgloss.Color("#F38181") // Soft red
	infoColor      = lipgloss.Color("#6C5CE7") // Purple

	// UI colors
	subtleColor    = lipgloss.Color("#6B7280") // Gray
	borderColor    = lipgloss.Color("#374151") // Dark gray
	bgColor        = lipgloss.Color("#1F2937") // Very dark gray

	// Text colors
	textColor      = lipgloss.Color("#F9FAFB") // Almost white
	dimTextColor   = lipgloss.Color("#9CA3AF") // Light gray
)

// Styles
var (
	titleStyle = lipgloss.NewStyle().
		Foreground(primaryColor).
		Bold(true).
		PaddingTop(1).
		PaddingBottom(1)

	bannerStyle = lipgloss.NewStyle().
		Foreground(accentColor).
		Bold(true).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(borderColor).
		Padding(1, 2).
		Margin(1, 0)

	boxStyle = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(borderColor).
		Padding(1, 2).
		Margin(1, 0)

	statStyle = lipgloss.NewStyle().
		Foreground(textColor).
		PaddingRight(2)

	statLabelStyle = lipgloss.NewStyle().
		Foreground(dimTextColor).
		PaddingRight(1)

	statValueStyle = lipgloss.NewStyle().
		Foreground(accentColor).
		Bold(true)

	pathStyle = lipgloss.NewStyle().
		Foreground(dimTextColor).
		Italic(true).
		MaxWidth(80)

	criticalStyle = lipgloss.NewStyle().
		Foreground(errorColor).
		Bold(true)

	warningStyle = lipgloss.NewStyle().
		Foreground(warningColor).
		Bold(true)

	infoStyle = lipgloss.NewStyle().
		Foreground(infoColor).
		Bold(true)

	successStyle = lipgloss.NewStyle().
		Foreground(successColor).
		Bold(true)

	subtleStyle = lipgloss.NewStyle().
		Foreground(subtleColor)

	headerStyle = lipgloss.NewStyle().
		Foreground(primaryColor).
		Bold(true).
		Underline(true).
		PaddingBottom(1)
)

// ScanModel is the bubbletea model for the scan progress
type ScanModel struct {
	progress      progress.Model
	spinner       spinner.Model
	scanPath      string
	destURL       string
	startTime     time.Time
	currentStats  *models.ScanProgress
	done          bool
	err           error
	width         int
	height        int
}

// NewScanModel creates a new scan progress model
func NewScanModel(scanPath, destURL string) ScanModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(accentColor)

	p := progress.New(
		progress.WithDefaultGradient(),
		progress.WithWidth(60),
	)

	return ScanModel{
		spinner:   s,
		progress:  p,
		scanPath:  scanPath,
		destURL:   destURL,
		startTime: time.Now(),
		width:     80,
		height:    24,
	}
}

// Init initializes the model
func (m ScanModel) Init() tea.Cmd {
	return tea.Batch(m.spinner.Tick, tea.EnterAltScreen)
}

// Update handles messages
func (m ScanModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		}

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case ProgressMsg:
		m.currentStats = (*models.ScanProgress)(msg)
		return m, nil

	case DoneMsg:
		m.done = true
		return m, tea.Quit

	case ErrorMsg:
		m.err = error(msg)
		m.done = true
		return m, tea.Quit
	}

	return m, nil
}

// View renders the UI
func (m ScanModel) View() string {
	if m.err != nil {
		return m.renderError()
	}

	if m.done {
		return ""
	}

	return m.renderProgress()
}

func (m ScanModel) renderProgress() string {
	var b strings.Builder

	// Header with spinner
	header := fmt.Sprintf("%s  Scanning SharePoint Migration Readiness", m.spinner.View())
	b.WriteString(titleStyle.Render(header))
	b.WriteString("\n\n")

	// Scan path info
	pathBox := boxStyle.Width(m.width - 4).Render(
		statLabelStyle.Render("Path:") + " " + pathStyle.Render(m.scanPath) + "\n" +
			statLabelStyle.Render("Destination:") + " " + pathStyle.Render(m.destURL),
	)
	b.WriteString(pathBox)
	b.WriteString("\n")

	if m.currentStats != nil {
		// Stats grid
		elapsed := time.Since(m.startTime)
		rate := float64(m.currentStats.ItemsScanned) / elapsed.Seconds()

		stats := m.renderStatsGrid(m.currentStats, elapsed, rate)
		b.WriteString(boxStyle.Width(m.width - 4).Render(stats))
		b.WriteString("\n")

		// Progress bar (indeterminate for now)
		if m.currentStats.ItemsScanned > 0 {
			progressBar := m.progress.ViewAs(0.5) // Indeterminate progress
			b.WriteString("  " + progressBar + "\n\n")
		}

		// Current path being scanned
		if m.currentStats.CurrentPath != "" {
			currentPath := m.currentStats.CurrentPath
			if len(currentPath) > 80 {
				currentPath = "..." + currentPath[len(currentPath)-77:]
			}
			b.WriteString(subtleStyle.Render("  └─ ") + pathStyle.Render(currentPath))
			b.WriteString("\n")
		}
	}

	// Help text
	b.WriteString("\n")
	b.WriteString(subtleStyle.Render("  Press ctrl+c to cancel"))

	return b.String()
}

func (m ScanModel) renderStatsGrid(stats *models.ScanProgress, elapsed time.Duration, rate float64) string {
	var b strings.Builder

	// Row 1: Items and Files
	b.WriteString(
		statLabelStyle.Render("Items:") + " " + statValueStyle.Render(formatNumber(stats.ItemsScanned)) + "    " +
		statLabelStyle.Render("Files:") + " " + statValueStyle.Render(formatNumber(stats.FilesScanned)) + "    " +
		statLabelStyle.Render("Folders:") + " " + statValueStyle.Render(formatNumber(stats.DirsScanned)) + "\n",
	)

	// Row 2: Size and Rate
	b.WriteString(
		statLabelStyle.Render("Size:") + " " + statValueStyle.Render(formatBytes(stats.BytesScanned)) + "    " +
		statLabelStyle.Render("Rate:") + " " + statValueStyle.Render(fmt.Sprintf("%s/sec", formatNumber(int64(rate)))) + "    " +
		statLabelStyle.Render("Time:") + " " + statValueStyle.Render(formatDuration(elapsed)),
	)

	// Row 3: Issues
	if stats.IssuesFound > 0 {
		b.WriteString("\n")
		b.WriteString(
			statLabelStyle.Render("Issues:") + " " + warningStyle.Render(formatNumber(int64(stats.IssuesFound))),
		)
	}

	return b.String()
}

func (m ScanModel) renderError() string {
	var b strings.Builder

	b.WriteString("\n")
	b.WriteString(lipgloss.NewStyle().Foreground(errorColor).Render("✗") + " " + titleStyle.Render("Error"))
	b.WriteString("\n\n")

	errorBox := boxStyle.
		BorderForeground(errorColor).
		Width(m.width - 4).
		Render(m.err.Error())

	b.WriteString(errorBox)
	b.WriteString("\n")

	return b.String()
}

// Custom message types for bubbletea
type ProgressMsg *models.ScanProgress
type DoneMsg struct{}
type ErrorMsg error

// ShowStyledBanner displays a Claude Code-inspired banner
func ShowStyledBanner() {
	banner := `
 _____ ____  ____  _____    _    ______   __
/ ____|  _ \|  _ \| ____|  / \  |  _ \ \ / /
\___ \| |_) | |_) |  _|   / _ \ | | | \ V /
 ___) |  __/|  _ <| |___ / ___ \| |_| || |
|____/|_|   |_| \_\_____/_/   \_\____/ |_|
`

	styledBanner := bannerStyle.Render(
		lipgloss.NewStyle().Foreground(accentColor).Render(banner) + "\n\n" +
		lipgloss.NewStyle().Foreground(textColor).Render("SharePoint Online Migration Readiness Scanner") + "\n" +
		subtleStyle.Render("Built for Speed & Scale • Go Edition v2.0"),
	)

	fmt.Println(styledBanner)
}

// ShowStyledSummary displays the final results with Claude Code styling
func ShowStyledSummary(result *models.ScanResult) {
	fmt.Println()

	// Success header
	header := "✓ Scan Complete"
	if result.Summary.BySeverity[models.SeverityCritical] > 0 {
		header = "⚠ Scan Complete - Issues Found"
	}

	fmt.Println(bannerStyle.Render(headerStyle.Render(header)))
	fmt.Println()

	// Stats section
	statsBox := renderStatsBox(result)
	fmt.Println(boxStyle.Width(80).Render(statsBox))
	fmt.Println()

	// Issues summary
	if result.IssuesFound > 0 {
		issuesBox := renderIssuesBox(result)
		fmt.Println(boxStyle.Width(80).Render(issuesBox))
		fmt.Println()

		// Issue types breakdown
		typesBox := renderIssueTypesBox(result)
		fmt.Println(boxStyle.Width(80).Render(typesBox))
		fmt.Println()
	}

	// Recommendation
	recommendation := renderRecommendation(result)
	fmt.Println(recommendation)
	fmt.Println()
}

func renderStatsBox(result *models.ScanResult) string {
	var b strings.Builder

	b.WriteString(headerStyle.Render("Scan Statistics"))
	b.WriteString("\n\n")

	// Path
	b.WriteString(statLabelStyle.Render("Path:") + "         " + lipgloss.NewStyle().Foreground(textColor).Render(result.ScanPath) + "\n")

	// Duration
	b.WriteString(statLabelStyle.Render("Duration:") + "     " + statValueStyle.Render(formatDuration(result.Duration)) + "\n")

	// Items
	itemsText := fmt.Sprintf("%s (%s files, %s folders)",
		formatNumber(result.TotalItems),
		formatNumber(result.TotalFiles),
		formatNumber(result.TotalFolders))
	b.WriteString(statLabelStyle.Render("Items:") + "        " + lipgloss.NewStyle().Foreground(textColor).Render(itemsText) + "\n")

	// Size
	b.WriteString(statLabelStyle.Render("Total Size:") + "   " + statValueStyle.Render(formatBytes(result.TotalSize)) + "\n")

	// Rate
	rate := float64(result.TotalItems) / result.Duration.Seconds()
	b.WriteString(statLabelStyle.Render("Scan Rate:") + "    " + statValueStyle.Render(fmt.Sprintf("%s items/sec", formatNumber(int64(rate)))))

	return b.String()
}

func renderIssuesBox(result *models.ScanResult) string {
	var b strings.Builder

	b.WriteString(headerStyle.Render(fmt.Sprintf("Issues Found: %s", formatNumber(int64(result.IssuesFound)))))
	b.WriteString("\n\n")

	critical := result.Summary.BySeverity[models.SeverityCritical]
	warning := result.Summary.BySeverity[models.SeverityWarning]
	info := result.Summary.BySeverity[models.SeverityInfo]

	if critical > 0 {
		b.WriteString(criticalStyle.Render("● Critical: ") +
			criticalStyle.Render(formatNumber(int64(critical))) +
			subtleStyle.Render("  (requires immediate action)") + "\n")
	}

	if warning > 0 {
		b.WriteString(warningStyle.Render("● Warning:  ") +
			warningStyle.Render(formatNumber(int64(warning))) +
			subtleStyle.Render("  (recommended to fix)") + "\n")
	}

	if info > 0 {
		b.WriteString(infoStyle.Render("● Info:     ") +
			infoStyle.Render(formatNumber(int64(info))) +
			subtleStyle.Render("  (review recommended)"))
	}

	return b.String()
}

func renderIssueTypesBox(result *models.ScanResult) string {
	var b strings.Builder

	b.WriteString(headerStyle.Render("Issue Types Breakdown"))
	b.WriteString("\n\n")

	// Sort issue types for consistent display
	types := []models.IssueType{
		models.IssuePathLength,
		models.IssueInvalidCharacters,
		models.IssueReservedName,
		models.IssueBlockedFileType,
		models.IssueProblematicFile,
		models.IssueFileSize,
		models.IssueNameConflict,
		models.IssueHiddenFile,
		models.IssueSystemFile,
	}

	for _, issueType := range types {
		if count, exists := result.Summary.ByType[issueType]; exists && count > 0 {
			icon := getIssueIcon(issueType)
			typeName := string(issueType)

			// Pad type name for alignment
			padding := strings.Repeat(" ", 22 - len(typeName))

			b.WriteString(lipgloss.NewStyle().Foreground(accentColor).Render(icon) + " " +
				lipgloss.NewStyle().Foreground(textColor).Render(typeName) + padding +
				statValueStyle.Render(formatNumber(int64(count))) + "\n")
		}
	}

	return b.String()
}

func renderRecommendation(result *models.ScanResult) string {
	critical := result.Summary.BySeverity[models.SeverityCritical]
	warning := result.Summary.BySeverity[models.SeverityWarning]

	var icon, status, message string
	var style lipgloss.Style

	if critical > 0 {
		icon = "!"
		status = "Action Required"
		message = "Critical issues must be resolved before migration.\nReview the detailed report for remediation steps."
		style = criticalStyle
	} else if warning > 0 {
		icon = "▲"
		status = "Warnings Detected"
		message = "Address warnings to avoid potential issues during migration.\nReview the detailed report for recommendations."
		style = warningStyle
	} else if result.IssuesFound > 0 {
		icon = "i"
		status = "Review Recommended"
		message = "Only informational items found.\nReview and proceed with migration planning."
		style = infoStyle
	} else {
		icon = "✓"
		status = "Ready for Migration"
		message = "No issues found! This path is ready for SharePoint Online migration."
		style = successStyle
	}

	header := icon + " " + status
	content := style.Render(header) + "\n\n" + subtleStyle.Render(message)

	return boxStyle.
		BorderForeground(style.GetForeground()).
		Width(80).
		Render(content)
}

func getIssueIcon(issueType models.IssueType) string {
	switch issueType {
	case models.IssuePathLength:
		return "→"
	case models.IssueInvalidCharacters:
		return "×"
	case models.IssueReservedName:
		return "!"
	case models.IssueBlockedFileType:
		return "■"
	case models.IssueProblematicFile:
		return "▲"
	case models.IssueFileSize:
		return "+"
	case models.IssueNameConflict:
		return "≠"
	case models.IssueHiddenFile:
		return "·"
	case models.IssueSystemFile:
		return "*"
	default:
		return "•"
	}
}

// Helper functions (same as before but needed here)
func formatNumber(n int64) string {
	if n < 1000 {
		return fmt.Sprintf("%d", n)
	}
	str := fmt.Sprintf("%d", n)
	result := ""
	for i, c := range str {
		if i > 0 && (len(str)-i)%3 == 0 {
			result += ","
		}
		result += string(c)
	}
	return result
}

func formatBytes(bytes int64) string {
	if bytes == 0 {
		return "0 B"
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

func formatDuration(d time.Duration) string {
	if d < time.Second {
		return fmt.Sprintf("%dms", d.Milliseconds())
	}
	if d < time.Minute {
		return fmt.Sprintf("%.1fs", d.Seconds())
	}
	if d < time.Hour {
		minutes := int(d.Minutes())
		seconds := int(d.Seconds()) % 60
		return fmt.Sprintf("%dm%ds", minutes, seconds)
	}
	hours := int(d.Hours())
	minutes := int(d.Minutes()) % 60
	return fmt.Sprintf("%dh%dm", hours, minutes)
}

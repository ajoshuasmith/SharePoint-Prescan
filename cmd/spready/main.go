package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/ajoshuasmith/sharepoint-prescan/internal/config"
	"github.com/ajoshuasmith/sharepoint-prescan/internal/models"
	"github.com/ajoshuasmith/sharepoint-prescan/internal/reporter"
	"github.com/ajoshuasmith/sharepoint-prescan/internal/scanner"
	"github.com/ajoshuasmith/sharepoint-prescan/internal/ui"
	"github.com/ajoshuasmith/sharepoint-prescan/internal/validator"
)

var (
	version = "2.0.0"
	commit  = "dev"
)

func main() {
	// Command line flags
	scanPath := flag.String("path", "", "Path to scan (required)")
	destinationURL := flag.String("destination", "", "SharePoint destination URL (optional)")
	outputDir := flag.String("output", ".", "Output directory for reports")
	outputJSON := flag.Bool("json", true, "Generate JSON report")
	outputCSV := flag.Bool("csv", true, "Generate CSV report")
	outputHTML := flag.Bool("html", true, "Generate HTML report")
	maxItems := flag.Int64("max-items", 0, "Maximum items to scan (0 = unlimited)")
	noBanner := flag.Bool("no-banner", false, "Suppress banner display")
	noProgress := flag.Bool("no-progress", false, "Suppress progress display")
	showVersion := flag.Bool("version", false, "Show version and exit")

	flag.Parse()

	// Show version
	if *showVersion {
		fmt.Printf("spready version %s (commit: %s)\n", version, commit)
		fmt.Println("SharePoint Online Migration Readiness Scanner - Go Edition")
		os.Exit(0)
	}

	// Validate required flags
	if *scanPath == "" {
		fmt.Println("Error: -path is required")
		flag.Usage()
		os.Exit(1)
	}

	// Validate path exists
	if _, err := os.Stat(*scanPath); os.IsNotExist(err) {
		ui.ShowError(fmt.Sprintf("Path does not exist: %s", *scanPath), nil)
		os.Exit(1)
	}

	// Get absolute path
	absPath, err := filepath.Abs(*scanPath)
	if err != nil {
		ui.ShowError("Failed to resolve absolute path", err)
		os.Exit(1)
	}

	// Show banner
	if !*noBanner {
		ui.ShowStyledBanner()
		fmt.Printf("\n")
	}

	// Initialize configuration
	cfg := config.NewDefaultConfig()

	scnr := scanner.NewScanner(absPath, cfg.Settings.DefaultExcludeFolders, *maxItems)

	// Create validator
	v := validator.NewValidator(cfg, *destinationURL, cfg.Settings.DefaultChecks)

	// Setup context with cancellation
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigChan
		fmt.Println("\n\n⚠️  Scan interrupted by user. Generating partial results...")
		cancel()
	}()

	// Start scan
	startTime := time.Now()
	itemsChan, progressChan, errChan := scnr.Scan(ctx)

	// Process items and show progress
	var (
		totalItems   int64
		totalFiles   int64
		totalFolders int64
		totalSize    int64
		issues       []models.Issue
	)

	// Progress update ticker
	progressTicker := time.NewTicker(500 * time.Millisecond)
	defer progressTicker.Stop()

	var lastProgress *models.ScanProgress

	done := false
	for !done {
		select {
		case item, ok := <-itemsChan:
			if !ok {
				done = true
				break
			}

			// Count items
			totalItems++
			if item.IsDir {
				totalFolders++
			} else {
				totalFiles++
				totalSize += item.Size
			}

			// Validate item
			itemIssues := v.ValidateItem(item)
			issues = append(issues, itemIssues...)

		case progress, ok := <-progressChan:
			if ok {
				lastProgress = progress
				if lastProgress != nil {
					lastProgress.IssuesFound = len(issues)
				}
			}

		case <-progressTicker.C:
			if !*noProgress && lastProgress != nil {
				ui.ShowStyledProgress(lastProgress, startTime)
			}

		case err := <-errChan:
			if err != nil && err != context.Canceled {
				ui.ShowError("Scan error", err)
			}
		}
	}

	// Clear progress display
	if !*noProgress {
		ui.ClearStyledProgress()
	}

	// Calculate duration
	endTime := time.Now()
	duration := endTime.Sub(startTime)

	// Build summary
	summary := models.IssueSummary{
		ByType:     make(map[models.IssueType]int),
		BySeverity: make(map[models.Severity]int),
	}

	for _, issue := range issues {
		summary.ByType[issue.Type]++
		summary.BySeverity[issue.Severity]++
	}

	// Create scan result
	result := &models.ScanResult{
		ScanPath:       absPath,
		DestinationURL: *destinationURL,
		StartTime:      startTime,
		EndTime:        endTime,
		Duration:       duration,
		TotalItems:     totalItems,
		TotalFiles:     totalFiles,
		TotalFolders:   totalFolders,
		TotalSize:      totalSize,
		IssuesFound:    len(issues),
		Issues:         issues,
		Summary:        summary,
	}

	// Show summary
	ui.ShowStyledSummary(result)

	// Generate reports
	if *outputJSON || *outputCSV || *outputHTML {
		fmt.Println("\nGenerating reports...")

		// Ensure output directory exists
		if err := os.MkdirAll(*outputDir, 0755); err != nil {
			ui.ShowError("Failed to create output directory", err)
			os.Exit(1)
		}

		rep := reporter.NewReporter(*outputDir)

		if *outputJSON {
			if err := rep.GenerateJSON(result, ""); err != nil {
				ui.ShowError("Failed to generate JSON report", err)
			}
		}

		if *outputCSV {
			if err := rep.GenerateCSV(result, ""); err != nil {
				ui.ShowError("Failed to generate CSV report", err)
			}
		}

		if *outputHTML {
			if err := rep.GenerateHTML(result, ""); err != nil {
				ui.ShowError("Failed to generate HTML report", err)
			}
		}

		fmt.Println()
	}

	// Exit with appropriate code
	if summary.BySeverity[models.SeverityCritical] > 0 {
		ui.ShowWarning("Critical issues found. Exit code: 2")
		os.Exit(2)
	} else if summary.BySeverity[models.SeverityWarning] > 0 {
		ui.ShowInfo("Warnings found. Exit code: 1")
		os.Exit(1)
	}

	ui.ShowSuccess("Scan completed successfully!")
	os.Exit(0)
}

package validator

import (
	"net/url"
	"path/filepath"
	"strings"

	"github.com/ajoshuasmith/sharepoint-prescan/internal/config"
	"github.com/ajoshuasmith/sharepoint-prescan/internal/models"
)

// Validator performs validation checks on file system items
type Validator struct {
	config             *config.Config
	destinationURL     string
	destinationPathLen int
	enabledChecks      map[string]bool
}

// NewValidator creates a new Validator instance
func NewValidator(cfg *config.Config, destinationURL string, enabledChecks map[string]bool) *Validator {
	// Calculate destination path length for URL encoding
	destPathLen := destinationLength(destinationURL)

	if enabledChecks == nil {
		enabledChecks = cfg.Settings.DefaultChecks
	}

	return &Validator{
		config:             cfg,
		destinationURL:     destinationURL,
		destinationPathLen: destPathLen,
		enabledChecks:      enabledChecks,
	}
}

// ValidateItem runs all enabled validation checks on an item
func (v *Validator) ValidateItem(item *models.FileSystemItem) []models.Issue {
	var issues []models.Issue

	if v.enabledChecks["PathLength"] {
		issues = append(issues, v.checkPathLength(item)...)
	}

	if v.enabledChecks["InvalidCharacters"] {
		issues = append(issues, v.checkInvalidCharacters(item)...)
	}

	if v.enabledChecks["ReservedNames"] {
		issues = append(issues, v.checkReservedNames(item)...)
	}

	if !item.IsDir {
		ext := strings.ToLower(filepath.Ext(item.Name))

		if v.enabledChecks["BlockedFileTypes"] {
			issues = append(issues, v.checkBlockedFileTypes(item, ext)...)
		}

		if v.enabledChecks["ProblematicFiles"] {
			issues = append(issues, v.checkProblematicFiles(item, ext)...)
		}

		if v.enabledChecks["FileSize"] {
			issues = append(issues, v.checkFileSize(item)...)
		}
	}

	if v.enabledChecks["HiddenFiles"] && (item.IsHidden || item.IsSystem) {
		issues = append(issues, v.checkHiddenFiles(item)...)
	}

	return issues
}

// checkPathLength validates path length constraints
func (v *Validator) checkPathLength(item *models.FileSystemItem) []models.Issue {
	var issues []models.Issue

	// Check individual file/folder name length
	if len(item.Name) > v.config.SPOLimits.MaxFileNameLength {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssuePathLength,
			Severity: models.SeverityCritical,
			Message:  "File or folder name exceeds 255 character limit",
			Details:  formatLength(len(item.Name), v.config.SPOLimits.MaxFileNameLength),
			IsDirectory: item.IsDir,
			RemediationHint: formatRemediationHint("Rename to 255 characters or fewer. Current length: %d chars.", len(item.Name)),
		})
	}

	// Calculate URL-encoded path length
	relativePath := item.RelativePath
	if relativePath == "." {
		relativePath = ""
	}
	encodedPath := urlEncodePath(relativePath)
	totalLength := v.destinationPathLen
	if totalLength > 0 && encodedPath != "" {
		totalLength++
	}
	totalLength += len(encodedPath)

	maxLength := v.config.SPOLimits.MaxPathLength

	// Check if exceeds limit
	if totalLength > maxLength {
		overBy := totalLength - maxLength
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssuePathLength,
			Severity: models.SeverityCritical,
			Message:  "Path exceeds 400 character limit",
			Details:  formatLength(totalLength, maxLength),
			IsDirectory: item.IsDir,
			RemediationHint: formatRemediationHint("Shorten path by at least %d characters. Consider shortening folder names or reducing nesting depth.", overBy),
		})
	} else {
		// Check if approaching limit (warning threshold)
		thresholdPercent := v.config.Settings.PathWarningThresholdPercent
		warningThreshold := (maxLength * thresholdPercent) / 100

		if totalLength >= warningThreshold {
			remaining := maxLength - totalLength
			percentUsed := (totalLength * 100) / maxLength
			issues = append(issues, models.Issue{
				Path:     item.Path,
				Type:     models.IssuePathLength,
				Severity: models.SeverityWarning,
				Message:  formatMessage("Path is at %d%% of 400 character limit", percentUsed),
				Details:  formatLength(totalLength, maxLength),
				IsDirectory: item.IsDir,
				RemediationHint: formatRemediationHint("Only %d characters remaining. Consider shortening path to provide buffer for future growth.", remaining),
			})
		}
	}

	return issues
}

// checkInvalidCharacters validates against invalid characters
func (v *Validator) checkInvalidCharacters(item *models.FileSystemItem) []models.Issue {
	var issues []models.Issue
	var foundChars []rune

	for _, ch := range item.Name {
		if v.config.SPOLimits.InvalidCharsSet[ch] {
			foundChars = append(foundChars, ch)
		}
	}

	if len(foundChars) > 0 {
		charList := formatCharList(foundChars)
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueInvalidCharacters,
			Severity: models.SeverityCritical,
			Message:  "Contains invalid characters for SharePoint",
			Details:  formatMessage("Invalid characters found: %s", charList),
			IsDirectory: item.IsDir,
			RemediationHint: formatRemediationHint("Remove or replace these characters: %s", charList),
		})
	}

	// Check for blocked patterns
	nameLower := strings.ToLower(item.Name)
	for _, pattern := range v.config.SPOLimits.BlockedPatterns {
		if strings.Contains(nameLower, strings.ToLower(pattern)) {
			issues = append(issues, models.Issue{
				Path:     item.Path,
				Type:     models.IssueInvalidCharacters,
				Severity: models.SeverityCritical,
				Message:  "Contains blocked pattern",
				Details:  formatMessage("Blocked pattern '%s' found in name", pattern),
				IsDirectory: item.IsDir,
				RemediationHint: formatRemediationHint("Remove '%s' from the file/folder name", pattern),
			})
		}
	}

	// Check for blocked prefixes
	if !item.IsDir {
		for _, prefix := range v.config.SPOLimits.BlockedPrefixes.File {
			if strings.HasPrefix(item.Name, prefix) {
				issues = append(issues, models.Issue{
					Path:     item.Path,
					Type:     models.IssueInvalidCharacters,
					Severity: models.SeverityWarning,
					Message:  "File has blocked prefix",
					Details:  formatMessage("Files starting with '%s' may not sync properly", prefix),
					IsDirectory: false,
					RemediationHint: formatRemediationHint("Rename to remove '%s' prefix", prefix),
				})
			}
		}
	} else {
		for _, prefix := range v.config.SPOLimits.BlockedPrefixes.Folder {
			if strings.HasPrefix(item.Name, prefix) {
				issues = append(issues, models.Issue{
					Path:     item.Path,
					Type:     models.IssueInvalidCharacters,
					Severity: models.SeverityWarning,
					Message:  "Folder has blocked prefix",
					Details:  formatMessage("Folders starting with '%s' may not sync properly", prefix),
					IsDirectory: true,
					RemediationHint: formatRemediationHint("Rename to remove '%s' prefix", prefix),
				})
			}
		}
	}

	return issues
}

// checkReservedNames validates against reserved names
func (v *Validator) checkReservedNames(item *models.FileSystemItem) []models.Issue {
	var issues []models.Issue

	// Get name without extension for files
	nameToCheck := item.Name
	if !item.IsDir {
		nameToCheck = strings.TrimSuffix(item.Name, filepath.Ext(item.Name))
	}

	// Check against reserved names (case-insensitive)
	if v.config.SPOLimits.ReservedNamesSet[strings.ToUpper(nameToCheck)] {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueReservedName,
			Severity: models.SeverityCritical,
			Message:  "Uses a reserved name that is not allowed in SharePoint",
			Details:  formatMessage("'%s' is a reserved name", nameToCheck),
			IsDirectory: item.IsDir,
			RemediationHint: "Rename to a different name. Reserved names cannot be used in SharePoint.",
		})
	}

	return issues
}

// checkBlockedFileTypes validates against blocked file extensions
func (v *Validator) checkBlockedFileTypes(item *models.FileSystemItem, ext string) []models.Issue {
	var issues []models.Issue

	// Check executables
	if v.config.BlockedFileTypes.Executables.ExtensionsSet[ext] {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueBlockedFileType,
			Severity: models.SeverityWarning,
			Message:  v.config.BlockedFileTypes.Executables.Message,
			Category: "Blocked - Executable",
			Size:     item.Size,
			IsDirectory: false,
			RemediationHint: "Remove executable files or verify with SharePoint administrator if these files are needed.",
		})
		return issues
	}

	// Check scripts
	if v.config.BlockedFileTypes.Scripts.ExtensionsSet[ext] {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueBlockedFileType,
			Severity: models.SeverityWarning,
			Message:  v.config.BlockedFileTypes.Scripts.Message,
			Category: "Blocked - Script",
			Size:     item.Size,
			IsDirectory: false,
			RemediationHint: "Script files are often blocked for security. Check with SharePoint administrator.",
		})
		return issues
	}

	// Check system files
	if v.config.BlockedFileTypes.System.ExtensionsSet[ext] {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueBlockedFileType,
			Severity: models.SeverityWarning,
			Message:  v.config.BlockedFileTypes.System.Message,
			Category: "Blocked - System",
			Size:     item.Size,
			IsDirectory: false,
			RemediationHint: "System files typically cannot be uploaded to SharePoint Online.",
		})
		return issues
	}

	// Check dangerous file types
	if v.config.BlockedFileTypes.Dangerous.ExtensionsSet[ext] {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueBlockedFileType,
			Severity: models.SeverityWarning,
			Message:  v.config.BlockedFileTypes.Dangerous.Message,
			Category: "Blocked - Potentially Dangerous",
			Size:     item.Size,
			IsDirectory: false,
			RemediationHint: "This file type may be blocked for security reasons. Verify if needed.",
		})
		return issues
	}

	return issues
}

// checkProblematicFiles validates against files with known issues
func (v *Validator) checkProblematicFiles(item *models.FileSystemItem, ext string) []models.Issue {
	var issues []models.Issue

	// Check CAD files
	if v.config.ProblematicFiles.CAD.ExtensionsSet[ext] {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueProblematicFile,
			Severity: models.SeverityWarning,
			Message:  v.config.ProblematicFiles.CAD.Message,
			Category: v.config.ProblematicFiles.CAD.Category,
			Size:     item.Size,
			IsDirectory: false,
		})
		return issues
	}

	// Check Adobe files
	if v.config.ProblematicFiles.Adobe.ExtensionsSet[ext] {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueProblematicFile,
			Severity: models.SeverityWarning,
			Message:  v.config.ProblematicFiles.Adobe.Message,
			Category: v.config.ProblematicFiles.Adobe.Category,
			Size:     item.Size,
			IsDirectory: false,
		})
		return issues
	}

	// Check database files
	if v.config.ProblematicFiles.Database.ExtensionsSet[ext] {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueProblematicFile,
			Severity: models.SeverityWarning,
			Message:  v.config.ProblematicFiles.Database.Message,
			Category: v.config.ProblematicFiles.Database.Category,
			Size:     item.Size,
			IsDirectory: false,
		})
		return issues
	}

	// Check email archives (with size warning)
	if v.config.ProblematicFiles.EmailArchive.ExtensionsSet[ext] {
		severity := models.SeverityWarning
		if item.Size > v.config.ProblematicFiles.EmailArchive.SizeWarningBytes {
			severity = models.SeverityCritical
		}
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueProblematicFile,
			Severity: severity,
			Message:  v.config.ProblematicFiles.EmailArchive.Message,
			Category: v.config.ProblematicFiles.EmailArchive.Category,
			Size:     item.Size,
			IsDirectory: false,
		})
		return issues
	}

	// Check large media files
	if v.config.ProblematicFiles.LargeMedia.ExtensionsSet[ext] {
		if item.Size > v.config.ProblematicFiles.LargeMedia.SizeThresholdBytes {
			issues = append(issues, models.Issue{
				Path:     item.Path,
				Type:     models.IssueProblematicFile,
				Severity: models.SeverityInfo,
				Message:  v.config.ProblematicFiles.LargeMedia.Message,
				Category: v.config.ProblematicFiles.LargeMedia.Category,
				Size:     item.Size,
				IsDirectory: false,
			})
		}
		return issues
	}

	// Check virtual machine files
	if v.config.ProblematicFiles.VirtualMachine.ExtensionsSet[ext] {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueProblematicFile,
			Severity: models.SeverityWarning,
			Message:  v.config.ProblematicFiles.VirtualMachine.Message,
			Category: v.config.ProblematicFiles.VirtualMachine.Category,
			Size:     item.Size,
			IsDirectory: false,
		})
		return issues
	}

	// Check backup files
	if v.config.ProblematicFiles.Backup.ExtensionsSet[ext] {
		if item.Size > v.config.ProblematicFiles.Backup.SizeThresholdBytes {
			issues = append(issues, models.Issue{
				Path:     item.Path,
				Type:     models.IssueProblematicFile,
				Severity: models.SeverityInfo,
				Message:  v.config.ProblematicFiles.Backup.Message,
				Category: v.config.ProblematicFiles.Backup.Category,
				Size:     item.Size,
				IsDirectory: false,
			})
		}
		return issues
	}

	// Check OneNote files
	if v.config.ProblematicFiles.OneNote.ExtensionsSet[ext] {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueProblematicFile,
			Severity: models.SeverityInfo,
			Message:  v.config.ProblematicFiles.OneNote.Message,
			Category: v.config.ProblematicFiles.OneNote.Category,
			Size:     item.Size,
			IsDirectory: false,
		})
		return issues
	}

	// Check other file types
	if msg, exists := v.config.ProblematicFiles.Other[ext]; exists {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueProblematicFile,
			Severity: models.SeverityInfo,
			Message:  msg,
			Category: "Other",
			Size:     item.Size,
			IsDirectory: false,
		})
		return issues
	}

	// Check for secret files
	nameLower := strings.ToLower(item.Name)
	for pattern := range v.config.ProblematicFiles.Secrets.PatternsSet {
		if matchesPattern(nameLower, strings.ToLower(pattern)) {
			issues = append(issues, models.Issue{
				Path:     item.Path,
				Type:     models.IssueProblematicFile,
				Severity: models.SeverityWarning,
				Message:  v.config.ProblematicFiles.Secrets.Message,
				Category: "Security",
				Size:     item.Size,
				IsDirectory: false,
			})
			break
		}
	}

	return issues
}

// checkFileSize validates file size constraints
func (v *Validator) checkFileSize(item *models.FileSystemItem) []models.Issue {
	var issues []models.Issue

	// Check max file size
	if item.Size > v.config.SPOLimits.MaxFileSizeBytes {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueFileSize,
			Severity: models.SeverityCritical,
			Message:  "File exceeds 250 GB size limit",
			Details:  formatSize(item.Size),
			Size:     item.Size,
			IsDirectory: false,
			RemediationHint: "Split file or use alternative storage for files over 250 GB.",
		})
	} else if item.Size > v.config.Settings.FileSizeWarnings.Huge {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueFileSize,
			Severity: models.SeverityWarning,
			Message:  "Very large file may have sync issues",
			Details:  formatSize(item.Size),
			Size:     item.Size,
			IsDirectory: false,
			RemediationHint: "Files over 15 GB may experience slow sync or timeout issues.",
		})
	} else if item.Size > v.config.Settings.FileSizeWarnings.VeryLarge {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueFileSize,
			Severity: models.SeverityInfo,
			Message:  "Large file detected",
			Details:  formatSize(item.Size),
			Size:     item.Size,
			IsDirectory: false,
		})
	}

	return issues
}

// checkHiddenFiles validates hidden and system files
func (v *Validator) checkHiddenFiles(item *models.FileSystemItem) []models.Issue {
	var issues []models.Issue

	if item.IsHidden {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueHiddenFile,
			Severity: models.SeverityInfo,
			Message:  "Hidden file or folder",
			Details:  "Hidden files may not be needed in SharePoint",
			IsDirectory: item.IsDir,
			RemediationHint: "Review if this hidden item needs to be migrated.",
		})
	}

	if item.IsSystem {
		issues = append(issues, models.Issue{
			Path:     item.Path,
			Type:     models.IssueSystemFile,
			Severity: models.SeverityWarning,
			Message:  "System file or folder",
			Details:  "System files typically should not be migrated",
			IsDirectory: item.IsDir,
			RemediationHint: "Exclude system files from migration.",
		})
	}

	return issues
}

// Helper functions

func urlEncodePath(path string) string {
	// Normalize to forward slashes
	path = strings.ReplaceAll(path, "\\", "/")

	// Encode each segment separately to preserve slashes
	segments := strings.Split(path, "/")
	for i, segment := range segments {
		segments[i] = url.PathEscape(segment)
	}

	return strings.Join(segments, "/")
}

func destinationLength(destinationURL string) int {
	trimmed := strings.TrimRight(destinationURL, "/")
	if trimmed == "" {
		return 0
	}

	parsed, err := url.Parse(trimmed)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return len(trimmed)
	}

	parsed.RawQuery = ""
	parsed.Fragment = ""

	base := parsed.Scheme + "://" + parsed.Host
	escapedPath := strings.TrimRight(parsed.EscapedPath(), "/")
	if escapedPath != "" {
		base += escapedPath
	}

	return len(base)
}

func formatLength(current, max int) string {
	return formatMessage("%d / %d characters", current, max)
}

func formatSize(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return formatMessage("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return formatMessage("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

func formatCharList(chars []rune) string {
	var parts []string
	for _, ch := range chars {
		parts = append(parts, string(ch))
	}
	return strings.Join(parts, " ")
}

func formatMessage(format string, args ...interface{}) string {
	return strings.TrimSpace(formatRemediationHint(format, args...))
}

func formatRemediationHint(format string, args ...interface{}) string {
	if len(args) == 0 {
		return format
	}
	return formatString(format, args...)
}

func formatString(format string, args ...interface{}) string {
	// Simple formatting - replace %d, %s, %.1f, etc.
	result := format
	argIdx := 0

	for argIdx < len(args) {
		if strings.Contains(result, "%d") {
			result = strings.Replace(result, "%d", formatInt(args[argIdx]), 1)
			argIdx++
		} else if strings.Contains(result, "%s") {
			result = strings.Replace(result, "%s", formatArg(args[argIdx]), 1)
			argIdx++
		} else if strings.Contains(result, "%.1f") {
			result = strings.Replace(result, "%.1f", formatFloat(args[argIdx]), 1)
			argIdx++
		} else if strings.Contains(result, "%c") {
			result = strings.Replace(result, "%c", formatChar(args[argIdx]), 1)
			argIdx++
		} else {
			break
		}
	}

	return result
}

func formatInt(v interface{}) string {
	switch val := v.(type) {
	case int:
		return intToString(val)
	case int64:
		return int64ToString(val)
	default:
		return ""
	}
}

func formatFloat(v interface{}) string {
	if f, ok := v.(float64); ok {
		return float64ToString(f)
	}
	return ""
}

func formatChar(v interface{}) string {
	if s, ok := v.(string); ok && len(s) > 0 {
		return string(s[0])
	}
	return ""
}

func formatArg(v interface{}) string {
	if s, ok := v.(string); ok {
		return s
	}
	return formatInt(v)
}

func intToString(n int) string {
	if n == 0 {
		return "0"
	}

	var buf [20]byte
	i := len(buf) - 1
	neg := n < 0
	if neg {
		n = -n
	}

	for n > 0 {
		buf[i] = byte('0' + n%10)
		n /= 10
		i--
	}

	if neg {
		buf[i] = '-'
		i--
	}

	return string(buf[i+1:])
}

func int64ToString(n int64) string {
	return intToString(int(n))
}

func float64ToString(f float64) string {
	// Simple float formatting to 1 decimal place
	i := int64(f * 10)
	whole := i / 10
	frac := i % 10
	if frac < 0 {
		frac = -frac
	}
	return int64ToString(whole) + "." + intToString(int(frac))
}

func matchesPattern(name, pattern string) bool {
	// Simple pattern matching for * wildcards
	if !strings.Contains(pattern, "*") {
		return name == pattern
	}

	if strings.HasPrefix(pattern, "*") && strings.HasSuffix(pattern, "*") {
		// *pattern*
		return strings.Contains(name, strings.Trim(pattern, "*"))
	} else if strings.HasPrefix(pattern, "*") {
		// *pattern
		return strings.HasSuffix(name, strings.TrimPrefix(pattern, "*"))
	} else if strings.HasSuffix(pattern, "*") {
		// pattern*
		return strings.HasPrefix(name, strings.TrimSuffix(pattern, "*"))
	}

	return name == pattern
}

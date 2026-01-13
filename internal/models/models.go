package models

import "time"

// Severity levels for issues
type Severity string

const (
	SeverityCritical Severity = "Critical"
	SeverityWarning  Severity = "Warning"
	SeverityInfo     Severity = "Info"
)

// IssueType represents the category of the issue
type IssueType string

const (
	IssuePathLength        IssueType = "PathLength"
	IssueInvalidCharacters IssueType = "InvalidCharacters"
	IssueReservedName      IssueType = "ReservedName"
	IssueBlockedFileType   IssueType = "BlockedFileType"
	IssueProblematicFile   IssueType = "ProblematicFile"
	IssueFileSize          IssueType = "FileSize"
	IssueNameConflict      IssueType = "NameConflict"
	IssueHiddenFile        IssueType = "HiddenFile"
	IssueSystemFile        IssueType = "SystemFile"
)

// Issue represents a validation problem found during scanning
type Issue struct {
	Path            string    `json:"path"`
	Type            IssueType `json:"type"`
	Severity        Severity  `json:"severity"`
	Message         string    `json:"message"`
	Details         string    `json:"details,omitempty"`
	Category        string    `json:"category,omitempty"`
	Size            int64     `json:"size,omitempty"`
	IsDirectory     bool      `json:"isDirectory"`
	RemediationHint string    `json:"remediationHint,omitempty"`
}

// ScanResult represents the complete scan output
type ScanResult struct {
	ScanPath      string        `json:"scanPath"`
	DestinationURL string       `json:"destinationUrl,omitempty"`
	StartTime     time.Time     `json:"startTime"`
	EndTime       time.Time     `json:"endTime"`
	Duration      time.Duration `json:"duration"`
	TotalItems    int64         `json:"totalItems"`
	TotalFiles    int64         `json:"totalFiles"`
	TotalFolders  int64         `json:"totalFolders"`
	TotalSize     int64         `json:"totalSize"`
	IssuesFound   int           `json:"issuesFound"`
	Issues        []Issue       `json:"issues"`
	Summary       IssueSummary  `json:"summary"`
}

// IssueSummary provides a count of issues by type and severity
type IssueSummary struct {
	ByType     map[IssueType]int `json:"byType"`
	BySeverity map[Severity]int  `json:"bySeverity"`
}

// ScanProgress represents the current scan progress
type ScanProgress struct {
	ItemsScanned int64
	FilesScanned int64
	DirsScanned  int64
	BytesScanned int64
	IssuesFound  int
	CurrentPath  string
}

// FileSystemItem represents a file or folder being scanned
type FileSystemItem struct {
	Path        string
	Name        string
	IsDir       bool
	Size        int64
	ModTime     time.Time
	IsHidden    bool
	IsSystem    bool
	RelativePath string
}

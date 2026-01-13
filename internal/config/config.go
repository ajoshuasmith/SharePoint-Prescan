package config

import (
	"regexp"
	"strings"
)

// Config holds all SharePoint Online limits and validation rules
type Config struct {
	SPOLimits          *SPOLimits
	BlockedFileTypes   *BlockedFileTypes
	ProblematicFiles   *ProblematicFiles
	Settings           *Settings
}

// SPOLimits defines SharePoint Online restrictions
type SPOLimits struct {
	MaxPathLength     int
	MaxFileNameLength int
	MaxFileSizeBytes  int64
	InvalidCharacters []rune
	InvalidCharsSet   map[rune]bool // For O(1) lookup
	ReservedNames     []string
	ReservedNamesSet  map[string]bool
	BlockedPatterns   []string
	BlockedPrefixes   struct {
		File   []string
		Folder []string
	}
	RootLevelBlockedNames []string
}

// BlockedFileTypes defines file types that are blocked for security
type BlockedFileTypes struct {
	Executables FileTypeRule
	Scripts     FileTypeRule
	System      FileTypeRule
	Dangerous   FileTypeRule
	NoSync      FilePatternRule
	Temporary   FilePatternRule
}

// ProblematicFiles defines file types with known issues
type ProblematicFiles struct {
	CAD            ProblematicFileRule
	Adobe          ProblematicFileRule
	Database       ProblematicFileRule
	EmailArchive   ProblematicFileSizeRule
	LargeMedia     ProblematicFileSizeRule
	Development    FolderPatternRule
	Secrets        FilePatternRule
	LockFiles      FilePatternRule
	Bluebeam       BluebeamRule
	VirtualMachine ProblematicFileRule
	Backup         ProblematicFileSizeRule
	OneNote        ProblematicFileRule
	Other          map[string]string
}

// FileTypeRule defines a rule based on file extensions
type FileTypeRule struct {
	Extensions    []string
	ExtensionsSet map[string]bool // For O(1) lookup
	Severity      string
	Message       string
}

// FilePatternRule defines a rule based on file name patterns
type FilePatternRule struct {
	Patterns    []string
	PatternsSet map[string]bool
	Regexes     []*regexp.Regexp
	Severity    string
	Message     string
}

// ProblematicFileRule defines a problematic file type
type ProblematicFileRule struct {
	Extensions    []string
	ExtensionsSet map[string]bool
	Severity      string
	Category      string
	Message       string
}

// ProblematicFileSizeRule includes size thresholds
type ProblematicFileSizeRule struct {
	ProblematicFileRule
	SizeWarningBytes   int64
	SizeThresholdBytes int64
}

// FolderPatternRule defines folder patterns to detect
type FolderPatternRule struct {
	Patterns []string
	Severity string
	Category string
	Message  string
}

// BluebeamRule defines special Bluebeam PDF handling
type BluebeamRule struct {
	Extensions          []string
	PathThresholdChars  int
	Severity            string
	Category            string
	Message             string
	OnlyWarnOnLongPaths bool
}

// Settings holds scanner configuration
type Settings struct {
	PathWarningThresholdPercent int
	DefaultOutputFormats        []string
	DefaultChecks               map[string]bool
	FileSizeWarnings            struct {
		Large     int64
		VeryLarge int64
		Huge      int64
	}
	DefaultExcludeFolders   []string
	MaxItemsToScan          int64
	ProgressUpdateInterval  int
	ReportSettings          ReportSettings
	ConsoleSettings         ConsoleSettings
}

// ReportSettings controls report generation
type ReportSettings struct {
	IncludeAllItems    bool
	MaxIssuesInSummary int
	GroupByFolder      bool
	IncludeRemediation bool
	IncludeTimestamp   bool
	CompanyName        string
	ProjectName        string
}

// ConsoleSettings controls console output
type ConsoleSettings struct {
	UseColors       bool
	ShowProgressBar bool
	ShowBanner      bool
	VerboseOutput   bool
}

// NewDefaultConfig creates a new Config with SharePoint Online defaults
func NewDefaultConfig() *Config {
	cfg := &Config{
		SPOLimits:        newSPOLimits(),
		BlockedFileTypes: newBlockedFileTypes(),
		ProblematicFiles: newProblematicFiles(),
		Settings:         newDefaultSettings(),
	}

	// Build lookup sets for O(1) performance
	cfg.buildLookupSets()

	return cfg
}

func newSPOLimits() *SPOLimits {
	return &SPOLimits{
		MaxPathLength:     400,
		MaxFileNameLength: 255,
		MaxFileSizeBytes:  268435456000, // 250 GB
		InvalidCharacters: []rune{'"', '*', ':', '<', '>', '?', '/', '\\', '|'},
		ReservedNames: []string{
			".lock", "CON", "PRN", "AUX", "NUL",
			"COM0", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
			"LPT0", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
			"desktop.ini", "_vti_",
		},
		BlockedPatterns: []string{"_vti_"},
		RootLevelBlockedNames: []string{"forms"},
	}
}

func newBlockedFileTypes() *BlockedFileTypes {
	return &BlockedFileTypes{
		Executables: FileTypeRule{
			Extensions: []string{".exe", ".bat", ".cmd", ".com", ".scr", ".pif", ".msi", ".msp", ".application"},
			Severity:   "Warning",
			Message:    "Executable files are often blocked by SharePoint administrators for security reasons.",
		},
		Scripts: FileTypeRule{
			Extensions: []string{".vbs", ".vbe", ".js", ".jse", ".wsf", ".wsh", ".ps1", ".psm1", ".psd1", ".ps1xml", ".csh", ".ksh"},
			Severity:   "Warning",
			Message:    "Script files may be blocked by SharePoint administrators for security reasons.",
		},
		System: FileTypeRule{
			Extensions: []string{".dll", ".sys", ".drv", ".cpl", ".ocx"},
			Severity:   "Warning",
			Message:    "System files (.dll, .sys) are typically blocked in SharePoint Online.",
		},
		Dangerous: FileTypeRule{
			Extensions: []string{
				".ade", ".adp", ".app", ".asa", ".asp", ".aspx", ".bas", ".cer", ".chm", ".class",
				".cnt", ".crt", ".csh", ".der", ".fxp", ".gadget", ".grp", ".hlp", ".hpj", ".hta",
				".htc", ".htr", ".htw", ".ida", ".idc", ".idq", ".ins", ".isp", ".its", ".jar",
				".jse", ".ksh", ".lnk", ".mad", ".maf", ".mag", ".mam", ".maq", ".mar", ".mas",
				".mat", ".mau", ".mav", ".maw", ".mcf", ".mda", ".mdb", ".mde", ".mdt", ".mdw",
				".mdz", ".mht", ".mhtml", ".msc", ".msh", ".msh1", ".msh1xml", ".msh2", ".msh2xml",
				".mshxml", ".msp", ".mst", ".ops", ".pcd", ".pif", ".plg", ".prf", ".prg", ".printer",
				".pst", ".reg", ".rem", ".scf", ".scr", ".sct", ".shb", ".shs", ".shtm", ".shtml",
				".soap", ".stm", ".svc", ".url", ".vb", ".vbe", ".vbs", ".vsix", ".ws", ".wsc",
				".wsf", ".wsh", ".xamlx",
			},
			Severity: "Warning",
			Message:  "This file type may be blocked by SharePoint for security reasons.",
		},
		NoSync: FilePatternRule{
			Patterns: []string{"desktop.ini", ".ds_store", "thumbs.db", ".spotlight-*", ".trashes", ".fseventsd"},
			Severity: "Info",
			Message:  "System files that typically do not sync to SharePoint/OneDrive.",
		},
		Temporary: FilePatternRule{
			Patterns: []string{".tmp", ".temp", ".bak", ".swp", ".swo", "~*", "*.~*"},
			Severity: "Info",
			Message:  "Temporary files are typically not synced to SharePoint.",
		},
	}
}

func newProblematicFiles() *ProblematicFiles {
	return &ProblematicFiles{
		CAD: ProblematicFileRule{
			Extensions: []string{
				".dwg", ".dxf", ".dwl", ".dwl2",
				".rvt", ".rfa", ".rte", ".rft",
				".dgn",
				".sldprt", ".sldasm", ".slddrw",
				".ipt", ".iam", ".idw", ".ipn",
				".catpart", ".catproduct", ".catdrawing",
				".prt", ".asm", ".drw",
				".step", ".stp", ".iges", ".igs",
			},
			Severity: "Warning",
			Category: "CAD/BIM",
			Message:  "CAD files lack proper file locking in SharePoint. Multiple users can edit simultaneously without warning, causing data loss. Consider Autodesk Docs or dedicated file server for collaborative CAD work.",
		},
		Adobe: ProblematicFileRule{
			Extensions: []string{
				".psd", ".psb",
				".ai",
				".indd", ".indt", ".idml",
				".prproj", ".prel",
				".aep", ".aet",
				".fla", ".xfl",
				".xd",
				".idlk",
			},
			Severity: "Warning",
			Category: "Adobe Creative",
			Message:  "Adobe files cannot be opened directly from SharePoint. InDesign/Premiere linked files will break due to user-specific sync paths. Users must download to local drive first.",
		},
		Database: ProblematicFileRule{
			Extensions: []string{
				".mdb", ".accdb", ".accde", ".accdr", ".laccdb",
				".qbw", ".qbb", ".qbm", ".qbx",
				".nsf", ".ntf",
				".sqlite", ".sqlite3", ".db", ".db3",
				".dbf", ".fpt", ".cdx",
				".mdf", ".ldf", ".ndf",
				".fp7", ".fmp12",
			},
			Severity: "Warning",
			Category: "Database",
			Message:  "Database files require exclusive access and may corrupt when synced by multiple users. Migrate to cloud-native database solutions (SharePoint Lists, Power Apps, SQL Azure).",
		},
		EmailArchive: ProblematicFileSizeRule{
			ProblematicFileRule: ProblematicFileRule{
				Extensions: []string{".pst", ".ost"},
				Severity:   "Warning",
				Category:   "Email Archive",
				Message:    "PST files sync poorly - locked while Outlook runs and entire file (often 10-50GB) must re-upload after any change. Migrate to Exchange Online archive.",
			},
			SizeWarningBytes: 1073741824, // 1 GB
		},
		LargeMedia: ProblematicFileSizeRule{
			ProblematicFileRule: ProblematicFileRule{
				Extensions: []string{
					".mp4", ".mov", ".avi", ".mkv", ".wmv", ".m4v", ".webm", ".flv",
					".wav", ".aiff", ".aif", ".flac",
					".raw", ".cr2", ".cr3", ".nef", ".arw", ".dng", ".orf", ".rw2",
				},
				Severity: "Info",
				Category: "Large Media",
				Message:  "Large media files may experience slow sync. Consider Microsoft Stream for video hosting.",
			},
			SizeThresholdBytes: 5368709120, // 5 GB
		},
		Development: FolderPatternRule{
			Patterns: []string{
				"node_modules", ".git", "__pycache__", ".vs", ".idea", ".vscode",
				"bin", "obj", "packages", "vendor", ".nuget", "bower_components",
				".gradle", "target", "build", "dist",
			},
			Severity: "Warning",
			Category: "Development",
			Message:  "Development folders contain many small files that can exceed sync limits (100K files). Exclude from migration.",
		},
		Secrets: FilePatternRule{
			Patterns: []string{
				".env", ".env.*", "credentials.json", "secrets.json", "secrets.yaml", "secrets.yml",
				"*.pem", "*.key", "*.pfx", "*.p12", "id_rsa", "id_rsa.*", "id_ed25519", "id_ed25519.*",
				".htpasswd", "wp-config.php", "web.config",
			},
			Severity: "Warning",
			Message:  "This file may contain secrets or credentials. Review before migrating to shared storage.",
		},
		LockFiles: FilePatternRule{
			Patterns: []string{".dwl", ".dwl2", ".idlk", ".laccdb", ".ldb", "~$*", ".~*", "~*.tmp"},
			Severity: "Info",
			Message:  "Lock files block OneDrive sync while parent application is open. These will typically be skipped during migration.",
		},
		Bluebeam: BluebeamRule{
			Extensions:          []string{".pdf"},
			PathThresholdChars:  200,
			Severity:            "Info",
			Category:            "Bluebeam",
			Message:             "Bluebeam Revu has a 260-character path limit (stricter than SharePoint). Long paths may cause issues when opening in Bluebeam.",
			OnlyWarnOnLongPaths: true,
		},
		VirtualMachine: ProblematicFileRule{
			Extensions: []string{
				".vmdk", ".vhd", ".vhdx", ".vdi",
				".iso", ".img", ".dmg",
				".ova", ".ovf",
				".qcow", ".qcow2",
			},
			Severity: "Warning",
			Category: "Virtual Machine",
			Message:  "Virtual machine and disk images are very large and cannot be used directly from SharePoint. Consider Azure blob storage for VM images.",
		},
		Backup: ProblematicFileSizeRule{
			ProblematicFileRule: ProblematicFileRule{
				Extensions: []string{
					".bak", ".backup",
					".old", ".orig",
					".zip", ".7z", ".rar", ".tar", ".gz", ".tgz", ".tar.gz",
					".cab", ".arc",
				},
				Severity: "Info",
				Category: "Backup/Archive",
				Message:  "Backup and archive files work but cannot be previewed in SharePoint. Consider if these need to be migrated or archived separately.",
			},
			SizeThresholdBytes: 10737418240, // 10 GB
		},
		OneNote: ProblematicFileRule{
			Extensions: []string{".one", ".onetoc2"},
			Severity:   "Info",
			Category:   "OneNote",
			Message:    "OneNote section files should be migrated to OneNote Online notebooks instead of raw file migration.",
		},
		Other: map[string]string{
			".lnk":     "Windows shortcuts - paths may break after migration",
			".url":     "Internet shortcuts - generally work but verify links",
			".gdoc":    "Google Docs link - just a link file, no actual content",
			".gsheet":  "Google Sheets link - just a link file, no actual content",
			".gslides": "Google Slides link - just a link file, no actual content",
			".numbers": "Apple Numbers - no preview or collaboration in SharePoint",
			".pages":   "Apple Pages - no preview or collaboration in SharePoint",
			".key":     "Apple Keynote - no preview or collaboration in SharePoint",
			".vsdx":    "Visio - limited web viewing, requires Visio license",
			".mpp":     "MS Project - no web editing, requires Project license",
			".pub":     "Publisher - no web editing or preview",
		},
	}
}

func newDefaultSettings() *Settings {
	s := &Settings{
		PathWarningThresholdPercent: 80,
		DefaultOutputFormats:        []string{"HTML", "CSV"},
		DefaultChecks: map[string]bool{
			"PathLength":        true,
			"InvalidCharacters": true,
			"ReservedNames":     true,
			"BlockedFileTypes":  true,
			"ProblematicFiles":  true,
			"FileSize":          true,
			"NameConflicts":     true,
			"HiddenFiles":       true,
		},
		DefaultExcludeFolders:  []string{"$RECYCLE.BIN", "System Volume Information", "RECYCLER", ".Trash-*"},
		MaxItemsToScan:         0,
		ProgressUpdateInterval: 100,
		ReportSettings: ReportSettings{
			IncludeAllItems:    false,
			MaxIssuesInSummary: 1000,
			GroupByFolder:      true,
			IncludeRemediation: true,
			IncludeTimestamp:   true,
		},
		ConsoleSettings: ConsoleSettings{
			UseColors:       true,
			ShowProgressBar: true,
			ShowBanner:      true,
			VerboseOutput:   false,
		},
	}

	s.FileSizeWarnings.Large = 1073741824      // 1 GB
	s.FileSizeWarnings.VeryLarge = 5368709120  // 5 GB
	s.FileSizeWarnings.Huge = 15728640000      // ~15 GB

	return s
}

// buildLookupSets creates hash sets for O(1) lookups
func (c *Config) buildLookupSets() {
	// SPO Limits
	c.SPOLimits.InvalidCharsSet = make(map[rune]bool)
	for _, ch := range c.SPOLimits.InvalidCharacters {
		c.SPOLimits.InvalidCharsSet[ch] = true
	}

	c.SPOLimits.ReservedNamesSet = make(map[string]bool)
	for _, name := range c.SPOLimits.ReservedNames {
		c.SPOLimits.ReservedNamesSet[strings.ToUpper(name)] = true
	}

	c.SPOLimits.BlockedPrefixes.File = []string{"~$"}
	c.SPOLimits.BlockedPrefixes.Folder = []string{"~"}

	// Blocked file types
	c.BlockedFileTypes.Executables.ExtensionsSet = makeExtSet(c.BlockedFileTypes.Executables.Extensions)
	c.BlockedFileTypes.Scripts.ExtensionsSet = makeExtSet(c.BlockedFileTypes.Scripts.Extensions)
	c.BlockedFileTypes.System.ExtensionsSet = makeExtSet(c.BlockedFileTypes.System.Extensions)
	c.BlockedFileTypes.Dangerous.ExtensionsSet = makeExtSet(c.BlockedFileTypes.Dangerous.Extensions)

	c.BlockedFileTypes.NoSync.PatternsSet = makePatternSet(c.BlockedFileTypes.NoSync.Patterns)
	c.BlockedFileTypes.Temporary.PatternsSet = makePatternSet(c.BlockedFileTypes.Temporary.Patterns)

	// Problematic files
	c.ProblematicFiles.CAD.ExtensionsSet = makeExtSet(c.ProblematicFiles.CAD.Extensions)
	c.ProblematicFiles.Adobe.ExtensionsSet = makeExtSet(c.ProblematicFiles.Adobe.Extensions)
	c.ProblematicFiles.Database.ExtensionsSet = makeExtSet(c.ProblematicFiles.Database.Extensions)
	c.ProblematicFiles.EmailArchive.ExtensionsSet = makeExtSet(c.ProblematicFiles.EmailArchive.Extensions)
	c.ProblematicFiles.LargeMedia.ExtensionsSet = makeExtSet(c.ProblematicFiles.LargeMedia.Extensions)
	c.ProblematicFiles.VirtualMachine.ExtensionsSet = makeExtSet(c.ProblematicFiles.VirtualMachine.Extensions)
	c.ProblematicFiles.Backup.ExtensionsSet = makeExtSet(c.ProblematicFiles.Backup.Extensions)
	c.ProblematicFiles.OneNote.ExtensionsSet = makeExtSet(c.ProblematicFiles.OneNote.Extensions)

	c.ProblematicFiles.Secrets.PatternsSet = makePatternSet(c.ProblematicFiles.Secrets.Patterns)
	c.ProblematicFiles.LockFiles.PatternsSet = makePatternSet(c.ProblematicFiles.LockFiles.Patterns)
}

func makeExtSet(exts []string) map[string]bool {
	set := make(map[string]bool)
	for _, ext := range exts {
		set[strings.ToLower(ext)] = true
	}
	return set
}

func makePatternSet(patterns []string) map[string]bool {
	set := make(map[string]bool)
	for _, pattern := range patterns {
		set[strings.ToLower(pattern)] = true
	}
	return set
}

@{
    # Default Settings for SharePoint-Readiness Scanner

    # Warning threshold as percentage of path limit (e.g., 80 = warn when path is 80% of max)
    PathWarningThresholdPercent = 80

    # Default output formats to generate
    DefaultOutputFormats = @('HTML', 'CSV')

    # Default checks to run (all enabled by default)
    DefaultChecks = @{
        PathLength = $true
        InvalidCharacters = $true
        ReservedNames = $true
        BlockedFileTypes = $true
        ProblematicFiles = $true
        FileSize = $true
        NameConflicts = $true
        HiddenFiles = $true
    }

    # File size thresholds for warnings (in bytes)
    FileSizeWarnings = @{
        Large = 1073741824      # 1 GB - Info level
        VeryLarge = 5368709120  # 5 GB - Warning level
        Huge = 15728640000      # ~15 GB - Sync may fail
    }

    # Folders to exclude by default (common system folders)
    DefaultExcludeFolders = @(
        '$RECYCLE.BIN'
        'System Volume Information'
        'RECYCLER'
        '.Trash-*'
    )

    # Maximum items to scan (0 = unlimited)
    MaxItemsToScan = 0

    # Progress update interval (number of items between progress updates)
    ProgressUpdateInterval = 100

    # Report settings
    ReportSettings = @{
        IncludeAllItems = $false           # Include clean items in report (can be very large)
        MaxIssuesInSummary = 1000          # Max issues to show in HTML summary table
        GroupByFolder = $true              # Group issues by parent folder
        IncludeRemediation = $true         # Include fix suggestions
        IncludeTimestamp = $true           # Include scan timestamp in report
        CompanyName = ''                   # Optional company name for reports
        ProjectName = ''                   # Optional project name for reports
    }

    # Console output settings
    ConsoleSettings = @{
        UseColors = $true                  # Use colored output
        ShowProgressBar = $true            # Show progress bar during scan
        ShowBanner = $true                 # Show ASCII banner at start
        VerboseOutput = $false             # Show verbose details during scan
    }

    # Severity colors for console output
    SeverityColors = @{
        Critical = 'Red'
        Warning = 'Yellow'
        Info = 'Cyan'
        Success = 'Green'
    }
}

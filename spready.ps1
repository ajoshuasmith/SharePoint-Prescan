<#
.SYNOPSIS
    SharePoint-Readiness - Portable Single-File Scanner

.DESCRIPTION
    A standalone version of the SharePoint-Readiness scanner that requires no installation.
    Just download and run, or execute directly from the web.

.EXAMPLE
    irm ajoshuasmith.com/spready | iex

.EXAMPLE
    irm https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/spready.ps1 | iex

.EXAMPLE
    .\spready.ps1 -Path "C:\Data" -DestinationUrl "https://tenant.sharepoint.com/sites/Site/Docs"
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [Parameter()]
    [string]$DestinationUrl,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [ValidateSet('HTML', 'CSV', 'JSON', 'All')]
    [string[]]$OutputFormat = @('HTML', 'CSV'),

    [Parameter()]
    [int]$WarningThreshold = 80,

    [Parameter()]
    [string[]]$ExcludeDirs = @('$RECYCLE.BIN', '$Recycle.Bin', 'System Volume Information', 'RECYCLER'),

    [Parameter()]
    [int]$MaxIssuesInMemory = 200000,

    [Parameter()]
    [switch]$FastAttributes,

    [Parameter()]
    [switch]$Resume,

    [Parameter()]
    [int]$CheckpointInterval = 500
)

#region Configuration
$script:MaxPathLength = 400

$problematicExtensions = @{
    CAD = @('.dwg', '.dxf', '.rvt', '.rfa', '.dgn', '.sldprt', '.sldasm')
    Adobe = @('.psd', '.ai', '.indd', '.prproj', '.aep')
    Database = @('.mdb', '.accdb', '.qbw', '.qbb', '.sqlite', '.db')
    Email = @('.pst', '.ost')
}

# Pre-compiled lookups for performance (HashSets are O(1) vs array O(n))
$script:FastLookup = @{
    InvalidCharsSet = [System.Collections.Generic.HashSet[char]]::new([char[]]@('"', '*', ':', '<', '>', '?', '/', '\', '|'))
    ReservedNamesSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('.lock', 'CON', 'PRN', 'AUX', 'NUL', 'COM0', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT0', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    BlockedExtSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('.exe', '.bat', '.cmd', '.com', '.dll', '.scr', '.vbs', '.js', '.wsf', '.msi'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    # Flatten problematic extensions into category lookup
    ProblematicExtMap = @{}
}
# Build extension -> category map
foreach ($cat in $problematicExtensions.Keys) {
    foreach ($ext in $problematicExtensions[$cat]) {
        $script:FastLookup.ProblematicExtMap[$ext] = $cat
    }
}

# Pre-compiled regex for blocked patterns (compiled once, used millions of times)
$script:CompiledPatterns = @{
    VtiPattern = [regex]::new('_vti_', [System.Text.RegularExpressions.RegexOptions]::Compiled)
}

# Unicode characters for beautiful output
$script:UI = @{
    Check = [char]0x2713      # ✓
    Cross = [char]0x2717      # ✗
    Bullet = [char]0x2022     # •
    Arrow = [char]0x25B6      # ▶
    Circle = [char]0x25CF     # ●
    CircleEmpty = [char]0x25CB # ○
    BoxH = [char]0x2500       # ─
    BoxV = [char]0x2502       # │
    BoxTL = [char]0x250C      # ┌
    BoxTR = [char]0x2510      # ┐
    BoxBL = [char]0x2514      # └
    BoxBR = [char]0x2518      # ┘
    BoxT = [char]0x252C       # ┬
    BoxB = [char]0x2534       # ┴
    BoxL = [char]0x251C       # ├
    BoxR = [char]0x2524       # ┤
    ProgressFull = [char]0x2588  # █
    ProgressEmpty = [char]0x2591 # ░
    Spinner = @('|', '/', '-', '\')
}
#endregion

#region UI Functions
function Write-Banner {
    Clear-Host
    $banner = @"

    _____ _____    _____                _ _
   / ____|  __ \  |  __ \              | (_)
  | (___ | |__) | | |__) |___  __ _  __| |_ _ __   ___  ___ ___
   \___ \|  ___/  |  _  // _ \/ _`` |/ _`` | | '_ \ / _ \/ __/ __|
   ____) | |      | | \ \  __/ (_| | (_| | | | | |  __/\__ \__ \
  |_____/|_|      |_|  \_\___|\__,_|\__,_|_|_| |_|\___||___/___/

"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host "         SharePoint Migration Readiness Scanner" -ForegroundColor White
    Write-Host "                    Portable Edition v1.0" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Divider {
    param([string]$Char = "-", [int]$Width = 60, [string]$Color = 'DarkGray')
    Write-Host "  $("$Char" * $Width)" -ForegroundColor $Color
}

function Write-Step {
    param(
        [string]$Message,
        [ValidateSet('Pending', 'Running', 'Success', 'Error', 'Warning', 'Info')]
        [string]$Status = 'Running'
    )

    $icon = switch ($Status) {
        'Pending'  { $script:UI.CircleEmpty; 'DarkGray' }
        'Running'  { $script:UI.Circle; 'Cyan' }
        'Success'  { $script:UI.Check; 'Green' }
        'Error'    { $script:UI.Cross; 'Red' }
        'Warning'  { '!'; 'Yellow' }
        'Info'     { $script:UI.Bullet; 'Cyan' }
    }

    Write-Host "  " -NoNewline
    Write-Host $icon[0] -NoNewline -ForegroundColor $icon[1]
    Write-Host " $Message" -ForegroundColor White
}

function Write-Prompt {
    param([string]$Message)
    Write-Host ""
    Write-Host "  $($script:UI.Arrow) " -NoNewline -ForegroundColor Magenta
    Write-Host $Message -NoNewline -ForegroundColor White
    Write-Host ": " -NoNewline -ForegroundColor DarkGray
}

function Write-Info {
    param([string]$Label, [string]$Value, [string]$ValueColor = 'Cyan')
    Write-Host "    $($script:UI.BoxV) " -NoNewline -ForegroundColor DarkGray
    Write-Host $Label -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $ValueColor
}

function Write-TreeItem {
    param([string]$Message, [switch]$Last, [string]$Color = 'White', [string]$Badge = '', [string]$BadgeColor = 'Cyan')

    $connector = if ($Last) { $script:UI.BoxBL } else { $script:UI.BoxL }
    Write-Host "    $connector$($script:UI.BoxH)$($script:UI.BoxH) " -NoNewline -ForegroundColor DarkGray
    Write-Host $Message -NoNewline -ForegroundColor $Color
    if ($Badge) {
        Write-Host " $Badge" -ForegroundColor $BadgeColor
    } else {
        Write-Host ""
    }
}

function Write-ProgressBar {
    param(
        [int]$Percent,
        [int]$Width = 30,
        [string]$Label = ''
    )

    $filled = [Math]::Round($Width * ($Percent / 100))
    $empty = $Width - $filled

    $color = if ($Percent -ge 80) { 'Green' }
             elseif ($Percent -ge 50) { 'Yellow' }
             else { 'Red' }

    # Use ASCII characters for compatibility
    $bar = ("=" * $filled) + ("-" * $empty)

    Write-Host "`r    " -NoNewline
    Write-Host "[" -NoNewline -ForegroundColor DarkGray
    Write-Host $bar -NoNewline -ForegroundColor $color
    Write-Host "] " -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0,3}%" -f $Percent) -NoNewline -ForegroundColor $color
    if ($Label) {
        Write-Host " $Label" -NoNewline -ForegroundColor DarkGray
    }
}

#endregion

#region Helper Functions
function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Get-UrlEncodedLength {
    # Estimate URL-encoded path length (spaces become %20, special chars expand to %XX)
    param([string]$Path)
    $length = 0
    foreach ($char in $Path.ToCharArray()) {
        # Characters that get URL-encoded: space, #, %, &, +, and non-ASCII
        if ($char -eq ' ' -or $char -eq '#' -or $char -eq '%' -or $char -eq '&' -or $char -eq '+' -or [int]$char -gt 127) {
            $length += 3  # %XX encoding
        } else {
            $length += 1
        }
    }
    return $length
}

function Get-RobocopyItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter()]
        [string[]]$ExcludeDirs = @(),

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [int]$StartLine = 0,

        [Parameter()]
        [ref]$LineCounter
    )

    $robocopyCmd = Get-Command robocopy -ErrorAction SilentlyContinue
    if (-not $robocopyCmd) { return }

    $destPath = "C:\__SPREADYSINK__"
    $args = @(
        $SourcePath
        $destPath
        '/L'
        '/E'
        '/FP'
        '/BYTES'
        '/NJH'
        '/NJS'
        '/NC'
        '/NS'
        '/NP'
        '/R:0'
        '/W:0'
        '/XJ'
    )

    if ($ExcludeDirs.Count -gt 0) {
        $args += '/XD'
        $args += $ExcludeDirs
    }

    $quotedArgs = $args | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"', '""') + '"' } else { $_ }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $robocopyCmd.Source
    $psi.Arguments = ($quotedArgs -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $linePattern = '^\s*(?<tag>[A-Za-z ]+?)\s+(?<size>\d+)\s+(?<path>.+)$'
    $lineNumber = 0

    if ($LogPath -and (Test-Path $LogPath)) {
        $reader = [System.IO.StreamReader]::new($LogPath)
        try {
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                $lineNumber++
                if ($LineCounter) { $LineCounter.Value = $lineNumber }
                if ($lineNumber -le $StartLine) { continue }
                if (-not $line) { continue }
                if ($line -match $linePattern) {
                    $tag = $Matches['tag'].Trim()
                    $size = [long]$Matches['size']
                    $path = $Matches['path'].Trim()
                    if (-not $path) { continue }

                    $isDirectory = $tag -match '\bDir\b'

                    [PSCustomObject]@{
                        FullPath = $path
                        Size = $size
                        IsDirectory = $isDirectory
                    }
                }
            }
        } finally {
            $reader.Dispose()
        }
        return
    }

    $process = [System.Diagnostics.Process]::Start($psi)
    $writer = $null
    if ($LogPath) {
        $writer = [System.IO.StreamWriter]::new($LogPath, $false, [System.Text.Encoding]::UTF8)
    }

    try {
        while (-not $process.StandardOutput.EndOfStream) {
            $line = $process.StandardOutput.ReadLine()
            $lineNumber++
            if ($writer) { $writer.WriteLine($line) }
            if ($LineCounter) { $LineCounter.Value = $lineNumber }
            if ($lineNumber -le $StartLine) { continue }
            if (-not $line) { continue }
            if ($line -match $linePattern) {
                $tag = $Matches['tag'].Trim()
                $size = [long]$Matches['size']
                $path = $Matches['path'].Trim()
                if (-not $path) { continue }

                $isDirectory = $tag -match '\bDir\b'

                [PSCustomObject]@{
                    FullPath = $path
                    Size = $size
                    IsDirectory = $isDirectory
                }
            }
        }
    } finally {
        if ($writer) {
            $writer.Flush()
            $writer.Dispose()
        }
    }

    $process.WaitForExit() | Out-Null
}

function Get-ReadinessScore {
    param([int]$Critical, [int]$Warning)
    return [Math]::Max(0, 100 - [Math]::Min(50, $Critical * 2) - [Math]::Min(25, $Warning * 0.5))
}

function Get-MigrationRecommendations {
    param(
        [int]$TotalFiles,
        [long]$TotalSize,
        [array]$Issues,
        [object]$IssueStats,
        [int]$MaxDepth = 0
    )

    $recommendations = @()
    $sizeGB = [Math]::Round($TotalSize / 1GB, 1)

    # Count issue categories
    $hasIssueStats = $IssueStats -and $IssueStats.PSObject.Properties.Count -gt 0
    if ($hasIssueStats) {
        if ($IssueStats -is [hashtable]) {
            $cadFiles = [int]($IssueStats['CAD'])
            $adobeFiles = [int]($IssueStats['Adobe'])
            $dbFiles = [int]($IssueStats['Database'])
            $pstFiles = [int]($IssueStats['Email'])
            $pathIssues = [int]($IssueStats['PathIssues'])
        } else {
            $cadFiles = if ($IssueStats.PSObject.Properties.Name -contains 'CAD') { [int]$IssueStats.CAD } else { 0 }
            $adobeFiles = if ($IssueStats.PSObject.Properties.Name -contains 'Adobe') { [int]$IssueStats.Adobe } else { 0 }
            $dbFiles = if ($IssueStats.PSObject.Properties.Name -contains 'Database') { [int]$IssueStats.Database } else { 0 }
            $pstFiles = if ($IssueStats.PSObject.Properties.Name -contains 'Email') { [int]$IssueStats.Email } else { 0 }
            $pathIssues = if ($IssueStats.PSObject.Properties.Name -contains 'PathIssues') { [int]$IssueStats.PathIssues } else { 0 }
        }
    } else {
        $cadFiles = ($Issues | Where-Object { $_.Category -eq 'CAD' }).Count
        $adobeFiles = ($Issues | Where-Object { $_.Category -eq 'Adobe' }).Count
        $dbFiles = ($Issues | Where-Object { $_.Category -eq 'Database' }).Count
        $pstFiles = ($Issues | Where-Object { $_.Category -eq 'Email' }).Count
        $pathIssues = ($Issues | Where-Object { $_.Issue -in @('PathTooLong', 'PathNearLimit') }).Count
    }

    # Primary recommendation logic
    $primaryRec = $null
    $primaryReason = $null
    $primaryIcon = $null

    # Decision tree for primary recommendation
    if ($dbFiles -gt 0) {
        $primaryRec = "DO NOT MIGRATE databases to SharePoint"
        $primaryReason = "Found $dbFiles database files (.mdb, .accdb, .qbw). These WILL corrupt with cloud sync. Keep on-premises or use dedicated database hosting."
        $primaryIcon = "critical"
        $recommendations += [PSCustomObject]@{
            Priority = 1; Category = 'Critical'; Icon = 'critical'
            Title = "Database Files Detected"
            Recommendation = "Do NOT migrate $dbFiles database files to SharePoint/OneDrive"
            Details = "Database files require exclusive file locks and atomic writes. Cloud sync will cause corruption. Options: Keep on-premises file server, migrate to Azure SQL/cloud database, or use Azure Files with AD authentication."
            AffectedFiles = $dbFiles
        }
    }

    if ($cadFiles -gt 0) {
        if (-not $primaryRec) {
            $primaryRec = "Use Zee Drive or Cloud Drive Mapper"
            $primaryReason = "Found $cadFiles CAD/BIM files. Drive mapping provides file locking and maintains XREF paths that OneDrive sync breaks."
            $primaryIcon = "warning"
        }
        $recommendations += [PSCustomObject]@{
            Priority = 2; Category = 'CAD/BIM'; Icon = 'warning'
            Title = "CAD/BIM Files Require Special Handling"
            Recommendation = "Use drive mapping (Zee Drive, Cloud Drive Mapper) instead of OneDrive Sync"
            Details = "CAD files need: 1) File locking to prevent overwrites, 2) Consistent drive letters for XREFs, 3) No sync conflicts. OneDrive sync breaks all three. Consider: Zee Drive, Cloud Drive Mapper, or Autodesk BIM 360 for native CAD collaboration."
            AffectedFiles = $cadFiles
        }
    }

    if ($pstFiles -gt 0) {
        $recommendations += [PSCustomObject]@{
            Priority = 3; Category = 'Email'; Icon = 'warning'
            Title = "PST Files Should Not Sync"
            Recommendation = "Archive PSTs to Exchange Online or keep local - do not sync"
            Details = "PST files are locked while Outlook is open, causing constant sync failures. Any change re-uploads the entire file (often 2-50GB). Options: Import to Exchange Online mailbox/archive, use Microsoft 365 compliance archiving, or keep on local storage only."
            AffectedFiles = $pstFiles
        }
    }

    if ($adobeFiles -gt 0) {
        $recommendations += [PSCustomObject]@{
            Priority = 4; Category = 'Creative'; Icon = 'info'
            Title = "Adobe Creative Files Have Limitations"
            Recommendation = "Consider Adobe Creative Cloud or drive mapping for heavy users"
            Details = "Adobe files (.psd, .ai, .indd) can sync but: linked assets break when paths change, no co-authoring, large files slow sync. For occasional access OneDrive works, for active creative teams consider Adobe CC libraries or drive mapping."
            AffectedFiles = $adobeFiles
        }
    }

    # Size-based recommendations
    if ($TotalFiles -gt 300000) {
        if (-not $primaryRec) {
            $primaryRec = "Split into multiple libraries or use drive mapping"
            $primaryReason = "Exceeds OneDrive sync limit of 300,000 files. Sync client will fail or perform poorly."
            $primaryIcon = "critical"
        }
        $recommendations += [PSCustomObject]@{
            Priority = 1; Category = 'Scale'; Icon = 'critical'
            Title = "Exceeds OneDrive Sync Limit"
            Recommendation = "Do NOT sync all files - use OneDrive Shortcuts, split libraries, or drive mapping"
            Details = "Microsoft's sync limit is 300,000 files total. You have $($TotalFiles.ToString('N0')) files. Options: 1) Split into multiple site/libraries (<100K each), 2) Use OneDrive Shortcuts for selective access, 3) Use Zee Drive/Cloud Drive Mapper for full access without sync, 4) Archive inactive content."
            AffectedFiles = $TotalFiles
        }
    }
    elseif ($TotalFiles -gt 100000) {
        if (-not $primaryRec) {
            $primaryRec = "Use OneDrive Shortcuts (not full sync)"
            $primaryReason = "$($TotalFiles.ToString('N0')) files approaches sync limits. Shortcuts sync less metadata and perform better."
            $primaryIcon = "warning"
        }
        $recommendations += [PSCustomObject]@{
            Priority = 2; Category = 'Scale'; Icon = 'warning'
            Title = "Large Library - Performance Risk"
            Recommendation = "Use OneDrive Shortcuts instead of full library sync"
            Details = "With $($TotalFiles.ToString('N0')) files, OneDrive sync may be slow and unreliable. Shortcuts only sync metadata for accessed folders, dramatically improving performance. Split into departmental libraries if possible."
            AffectedFiles = $TotalFiles
        }
    }

    if ($sizeGB -gt 500) {
        $recommendations += [PSCustomObject]@{
            Priority = 3; Category = 'Storage'; Icon = 'warning'
            Title = "Large Data Volume ($sizeGB GB)"
            Recommendation = "Plan phased migration and consider archiving old data"
            Details = "Initial sync will take significant time (estimate: $([Math]::Round($sizeGB / 10, 0)) hours at 100Mbps). Consider: 1) Archive files not accessed in 2+ years to cold storage, 2) Migrate in phases by department/project, 3) Use Microsoft 365 Archive for inactive sites post-migration."
            AffectedFiles = $null
        }
    }

    # Path issues
    if ($pathIssues -gt 50) {
        $recommendations += [PSCustomObject]@{
            Priority = 4; Category = 'Paths'; Icon = 'warning'
            Title = "Significant Path Length Issues ($pathIssues items)"
            Recommendation = "Restructure folders or use shorter SharePoint URL"
            Details = "Many paths approach/exceed 400 char limit. Options: 1) Use shorter site name and library name, 2) Flatten deep folder structures, 3) Use OneDrive Shortcuts (shorter base path than full URL), 4) Rename lengthy folder names before migration."
            AffectedFiles = $pathIssues
        }
    }

    # Set primary recommendation if not already set
    if (-not $primaryRec) {
        if ($TotalFiles -lt 10000 -and $sizeGB -lt 50 -and $cadFiles -eq 0 -and $dbFiles -eq 0) {
            $primaryRec = "OneDrive Sync (Standard)"
            $primaryReason = "Small library ($($TotalFiles.ToString('N0')) files, $sizeGB GB) with no problematic file types. Ideal for OneDrive sync with full offline access."
            $primaryIcon = "success"
        }
        elseif ($TotalFiles -lt 50000) {
            $primaryRec = "OneDrive Sync or Shortcuts"
            $primaryReason = "Medium library suitable for OneDrive. Use Sync for offline needs, Shortcuts for lighter footprint."
            $primaryIcon = "success"
        }
        else {
            $primaryRec = "OneDrive Shortcuts"
            $primaryReason = "Larger library ($($TotalFiles.ToString('N0')) files). Shortcuts provide better performance than full sync."
            $primaryIcon = "info"
        }
    }

    # Alternative platforms recommendation
    $altPlatform = $null
    if ($dbFiles -gt 5 -or ($cadFiles -gt 50 -and $TotalFiles -gt 100000)) {
        $altPlatform = [PSCustomObject]@{
            Priority = 5; Category = 'Alternative'; Icon = 'info'
            Title = "Consider Alternative Platforms"
            Recommendation = "Evaluate alternative or hybrid approaches"
            Details = "Given the file types and scale, consider: **Azure Files** - SMB/NFS file shares with AD auth, ideal for legacy apps and lift-and-shift migrations. **Egnyte** - Purpose-built for AEC/engineering with CAD/BIM file handling and hybrid cloud+local storage. **Hybrid** - Keep CAD/databases on-premises, migrate documents to SharePoint."
            AffectedFiles = $null
        }
        $recommendations += $altPlatform
    }

    # Access method summary
    $accessMethods = @()
    $accessMethods += [PSCustomObject]@{
        Method = 'OneDrive Sync'
        BestFor = 'Small libraries (<50K files), users needing offline access'
        Avoid = 'CAD files, databases, >300K files'
        Verdict = if ($TotalFiles -lt 50000 -and $cadFiles -eq 0 -and $dbFiles -eq 0) { 'Recommended' } elseif ($TotalFiles -gt 300000 -or $dbFiles -gt 0) { 'Not Recommended' } else { 'Use Selectively' }
    }
    $accessMethods += [PSCustomObject]@{
        Method = 'OneDrive Shortcuts'
        BestFor = 'Large libraries, shared team content, multiple site access'
        Avoid = 'Users requiring full offline library access'
        Verdict = if ($TotalFiles -gt 50000 -and $cadFiles -eq 0 -and $dbFiles -eq 0) { 'Recommended' } else { 'Good Option' }
    }
    $accessMethods += [PSCustomObject]@{
        Method = 'Web Only'
        BestFor = 'Archival content, occasional access, compliance scenarios'
        Avoid = 'Daily working files, users with poor connectivity'
        Verdict = 'Supplementary'
    }
    $accessMethods += [PSCustomObject]@{
        Method = 'Zee Drive / Cloud Drive Mapper'
        BestFor = 'CAD/BIM, legacy apps needing drive letters, VDI environments'
        Avoid = 'Nothing - works for most scenarios but adds cost'
        Verdict = if ($cadFiles -gt 0 -or $dbFiles -gt 0 -or $TotalFiles -gt 300000) { 'Recommended' } else { 'Optional' }
    }
    $accessMethods += [PSCustomObject]@{
        Method = 'Azure Files'
        BestFor = 'Legacy apps needing SMB/NFS, lift-and-shift, large archives, hybrid w/ Azure File Sync'
        Avoid = 'Collaboration-focused teams, primarily Office documents'
        Verdict = if ($dbFiles -gt 3 -or $TotalSize -gt 500GB) { 'Consider' } else { 'Not Needed' }
    }
    $accessMethods += [PSCustomObject]@{
        Method = 'Egnyte'
        BestFor = 'AEC/engineering with CAD/BIM, hybrid cloud+local, compliance requirements'
        Avoid = 'M365-native workflows, budget-conscious orgs, simple doc sharing'
        Verdict = if ($cadFiles -gt 50 -or $adobeFiles -gt 50) { 'Consider' } else { 'Not Needed' }
    }

    return [PSCustomObject]@{
        PrimaryRecommendation = $primaryRec
        PrimaryReason = $primaryReason
        PrimaryIcon = $primaryIcon
        Recommendations = $recommendations | Sort-Object Priority
        AccessMethods = $accessMethods
        Stats = [PSCustomObject]@{
            TotalFiles = $TotalFiles
            TotalSizeGB = $sizeGB
            CADFiles = $cadFiles
            AdobeFiles = $adobeFiles
            DatabaseFiles = $dbFiles
            PSTFiles = $pstFiles
            PathIssues = $pathIssues
        }
    }
}

function Read-Input {
    param([string]$Prompt, [switch]$Required, [switch]$IsPath, [switch]$IsUrl, [string]$Default)

    while ($true) {
        Write-Prompt -Message $Prompt
        if ($Default) { Write-Host "[$Default] " -NoNewline -ForegroundColor DarkGray }
        $userInput = Read-Host

        if ([string]::IsNullOrWhiteSpace($userInput) -and $Default) {
            $userInput = $Default
        }

        if ([string]::IsNullOrWhiteSpace($userInput) -and $Required) {
            Write-Host "    $($script:UI.Cross) " -NoNewline -ForegroundColor Red
            Write-Host "This field is required." -ForegroundColor Red
            continue
        }

        if ($IsPath -and $userInput) {
            $userInput = $userInput.Trim('"', "'")
            if (-not (Test-Path $userInput -PathType Container)) {
                Write-Host "    $($script:UI.Cross) " -NoNewline -ForegroundColor Red
                Write-Host "Path not found: $userInput" -ForegroundColor Red
                continue
            }
            Write-Host "    $($script:UI.Check) " -NoNewline -ForegroundColor Green
            Write-Host "Path validated" -ForegroundColor Green
        }

        if ($IsUrl -and $userInput) {
            if (-not ($userInput -match '^https://')) {
                Write-Host "    $($script:UI.Cross) " -NoNewline -ForegroundColor Red
                Write-Host "Please enter a valid URL starting with https://" -ForegroundColor Red
                continue
            }
            try {
                [void][System.Uri]::new($userInput)
                Write-Host "    $($script:UI.Check) " -NoNewline -ForegroundColor Green
                Write-Host "URL validated" -ForegroundColor Green
            }
            catch {
                Write-Host "    $($script:UI.Cross) " -NoNewline -ForegroundColor Red
                Write-Host "Invalid URL format" -ForegroundColor Red
                continue
            }
        }

        return $userInput
    }
}
#endregion

#region Checkpoint & Progress Tracking
# Checkpoint file path (in output directory or temp)
$script:CheckpointPath = $null
$script:IncrementalPath = $null
$script:RobocopyLogPath = $null
$script:CheckpointLock = [System.Object]::new()
$script:IncrementalLock = [System.Object]::new()

# ETA tracking with rolling average
$script:ETATracker = @{
    StartTime = $null
    Samples = [System.Collections.Generic.List[double]]::new()
    MaxSamples = 20
    LastItemCount = 0
    LastSampleTime = $null
}

function Initialize-CheckpointSystem {
    param([string]$SourcePath, [string]$OutputDir)

    # Create checkpoint filename based on source path hash
    $pathHash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.MD5]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($SourcePath)
        )
    ).Replace("-", "").Substring(0, 8)

    $script:CheckpointPath = Join-Path $OutputDir "scan_checkpoint_$pathHash.json"
    $script:IncrementalPath = Join-Path $OutputDir "scan_issues_$pathHash.jsonl"
    $script:RobocopyLogPath = Join-Path $OutputDir "scan_robocopy_$pathHash.log"

    return @{
        CheckpointPath = $script:CheckpointPath
        IncrementalPath = $script:IncrementalPath
        RobocopyLogPath = $script:RobocopyLogPath
    }
}

function Get-ExistingCheckpoint {
    param(
        [string]$SourcePath,
        [string]$DestinationUrl
    )

    if (-not $script:CheckpointPath -or -not (Test-Path $script:CheckpointPath)) {
        return $null
    }

    try {
        $checkpoint = Get-Content $script:CheckpointPath -Raw | ConvertFrom-Json

        # Validate checkpoint matches current scan
        if ($checkpoint.SourcePath -ne $SourcePath) {
            Write-Host "    ! Checkpoint is for different path, ignoring" -ForegroundColor Yellow
            return $null
        }
        if ($DestinationUrl -and $checkpoint.DestinationUrl -and $checkpoint.DestinationUrl -ne $DestinationUrl) {
            Write-Host "    ! Checkpoint destination URL differs, ignoring" -ForegroundColor Yellow
            return $null
        }

        return $checkpoint
    } catch {
        Write-Host "    ! Could not read checkpoint: $_" -ForegroundColor Yellow
        return $null
    }
}

function Save-Checkpoint {
    param(
        [string]$SourcePath,
        [string]$DestinationUrl,
        [hashtable]$Counters,
        [System.Collections.Concurrent.ConcurrentDictionary[string,bool]]$ScannedDirs,
        [System.Collections.Concurrent.ConcurrentDictionary[string,long]]$FolderSizes,
        [System.Collections.Concurrent.ConcurrentDictionary[string,int]]$FolderFileCounts,
        [hashtable]$RobocopyState,
        [hashtable]$IssueCounts,
        [hashtable]$IssueStats
    )

    if (-not $script:CheckpointPath) { return }

    [System.Threading.Monitor]::Enter($script:CheckpointLock)
    try {
        $checkpoint = @{
            Version = 1
            Timestamp = (Get-Date).ToString('o')
            SourcePath = $SourcePath
            DestinationUrl = $DestinationUrl
            ItemCount = $Counters.ItemCount
            FileCount = $Counters.FileCount
            FolderCount = $Counters.FolderCount
            TotalSize = $Counters.TotalSize
            DirsProcessed = $Counters.DirsProcessed
            ScannedDirs = @($ScannedDirs.Keys)
            FolderSizes = @{}
            FolderFileCounts = @{}
        }

        if ($RobocopyState) {
            $checkpoint.RobocopyLogPath = $RobocopyState.LogPath
            $checkpoint.RobocopyLine = $RobocopyState.Line
            $checkpoint.RobocopyComplete = $RobocopyState.Complete
        }
        if ($RobocopyState -and $RobocopyState.LogPath -and (Test-Path $RobocopyState.LogPath)) {
            $logInfo = Get-Item -LiteralPath $RobocopyState.LogPath -ErrorAction SilentlyContinue
            if ($logInfo) {
                $checkpoint.RobocopyLogSize = $logInfo.Length
                $checkpoint.RobocopyLogLastWriteUtc = $logInfo.LastWriteTimeUtc.ToString('o')
            }
        }

        if ($IssueCounts) {
            $checkpoint.IssueCounts = $IssueCounts
        }
        if ($IssueStats) {
            $checkpoint.IssueStats = $IssueStats
        }

        # Copy folder data (limit to prevent huge checkpoint files)
        $count = 0
        foreach ($key in $FolderSizes.Keys) {
            $checkpoint.FolderSizes[$key] = $FolderSizes[$key]
            $count++
            if ($count -gt 10000) { break }
        }

        $count = 0
        foreach ($key in $FolderFileCounts.Keys) {
            $checkpoint.FolderFileCounts[$key] = $FolderFileCounts[$key]
            $count++
            if ($count -gt 10000) { break }
        }

        $checkpoint | ConvertTo-Json -Depth 5 -Compress | Out-File $script:CheckpointPath -Encoding UTF8 -Force
    } finally {
        [System.Threading.Monitor]::Exit($script:CheckpointLock)
    }
}

function Write-IncrementalIssue {
    param([hashtable]$Issue)

    if (-not $script:IncrementalPath) { return }

    [System.Threading.Monitor]::Enter($script:IncrementalLock)
    try {
        $json = $Issue | ConvertTo-Json -Compress
        Add-Content -Path $script:IncrementalPath -Value $json -Encoding UTF8
    } catch { }
    finally {
        [System.Threading.Monitor]::Exit($script:IncrementalLock)
    }
}

function Update-IssueAggregates {
    param(
        [hashtable]$Issue,
        [hashtable]$IssueCounts,
        [hashtable]$IssueStats
    )

    $IssueCounts.Total++
    switch ($Issue.Severity) {
        'Critical' { $IssueCounts.Critical++ }
        'Warning' { $IssueCounts.Warning++ }
        'Info' { $IssueCounts.Info++ }
    }

    switch ($Issue.Category) {
        'CAD' { $IssueStats.CAD++ }
        'Adobe' { $IssueStats.Adobe++ }
        'Database' { $IssueStats.Database++ }
        'Email' { $IssueStats.Email++ }
    }

    if ($Issue.Issue -eq 'PathTooLong' -or $Issue.Issue -eq 'PathNearLimit') {
        $IssueStats.PathIssues++
    }
}

function Add-IssueRecord {
    param(
        [hashtable]$Issue,
        [System.Collections.Concurrent.ConcurrentBag[hashtable]]$IssueBag,
        [hashtable]$IssueCounts,
        [hashtable]$IssueStats,
        [int]$MaxIssuesInMemory,
        [ref]$IssuesInMemoryCount,
        [ref]$IssuesTruncated
    )

    Update-IssueAggregates -Issue $Issue -IssueCounts $IssueCounts -IssueStats $IssueStats

    if ($MaxIssuesInMemory -le 0 -or $IssuesInMemoryCount.Value -lt $MaxIssuesInMemory) {
        $IssueBag.Add($Issue)
        $IssuesInMemoryCount.Value++
    }
    else {
        $IssuesTruncated.Value = $true
    }

    Write-IncrementalIssue -Issue $Issue
}

function Remove-CheckpointFiles {
    if ($script:CheckpointPath -and (Test-Path $script:CheckpointPath)) {
        Remove-Item $script:CheckpointPath -Force -ErrorAction SilentlyContinue
    }
}

function Update-ETATracker {
    param([long]$CurrentItems)

    $now = [DateTime]::UtcNow

    if (-not $script:ETATracker.StartTime) {
        $script:ETATracker.StartTime = $now
        $script:ETATracker.LastSampleTime = $now
        $script:ETATracker.LastItemCount = $CurrentItems
        return $null
    }

    $elapsed = ($now - $script:ETATracker.LastSampleTime).TotalSeconds
    if ($elapsed -lt 1) { return $null }  # Sample at most every second

    $itemsDelta = $CurrentItems - $script:ETATracker.LastItemCount
    if ($itemsDelta -gt 0) {
        $rate = $itemsDelta / $elapsed
        $script:ETATracker.Samples.Add($rate)

        # Keep rolling window
        while ($script:ETATracker.Samples.Count -gt $script:ETATracker.MaxSamples) {
            $script:ETATracker.Samples.RemoveAt(0)
        }
    }

    $script:ETATracker.LastSampleTime = $now
    $script:ETATracker.LastItemCount = $CurrentItems

    # Calculate average rate
    if ($script:ETATracker.Samples.Count -lt 3) { return $null }

    $avgRate = ($script:ETATracker.Samples | Measure-Object -Average).Average
    return $avgRate
}

function Format-RateString {
    param([double]$ItemsPerSecond)

    if ($ItemsPerSecond -ge 1000) {
        return "{0:N1}K/s" -f ($ItemsPerSecond / 1000)
    } else {
        return "{0:N0}/s" -f $ItemsPerSecond
    }
}
#endregion

#region Validators
# Optimized Test-Item using pre-compiled lookups for maximum speed
function Test-ItemFast {
    param(
        [string]$FullPath,
        [string]$Name,
        [bool]$IsFolder,
        [long]$FileSize,
        [System.IO.FileAttributes]$Attributes,
        [string]$RelativePath,
        [int]$DestPathLength,
        [int]$WarningThresholdPercent = 80,
        $ConflictTracker = $null,  # Pass $null to skip conflict checking
        [bool]$SkipConflictCheck = $false
    )

    $issues = [System.Collections.Generic.List[hashtable]]::new()
    $maxPathLength = $script:MaxPathLength
    # Use URL-encoded length to account for spaces/%20 expansion
    $encodedRelativeLen = Get-UrlEncodedLength -Path $RelativePath
    $fullPathLen = $DestPathLength + $encodedRelativeLen
    $type = if ($IsFolder) { 'Folder' } else { 'File' }
    $sizeFormatted = if (-not $IsFolder -and $FileSize -gt 0) { Format-FileSize $FileSize } else { '' }

    # Path length checks (using URL-encoded length)
    if ($fullPathLen -gt $maxPathLength) {
        $over = $fullPathLen - $maxPathLength
        $issues.Add(@{
            Severity = 'Critical'; Issue = 'PathTooLong'; Category = 'Path Length'
            Path = $FullPath; Name = $Name; Type = $type
            Size = $FileSize; SizeFormatted = $sizeFormatted
            IssueDescription = "URL-encoded path length $fullPathLen/$maxPathLength chars (exceeds by $over)"
            Suggestion = "Shorten path by $over characters or remove spaces/special chars"
        })
    }
    elseif ($WarningThresholdPercent -gt 0) {
        $warningThreshold = [Math]::Floor($maxPathLength * ($WarningThresholdPercent / 100))
        if ($fullPathLen -ge $warningThreshold) {
            $pct = [int](($fullPathLen / $maxPathLength) * 100)
            $issues.Add(@{
                Severity = 'Warning'; Issue = 'PathNearLimit'; Category = 'Path Length'
                Path = $FullPath; Name = $Name; Type = $type
                Size = $FileSize; SizeFormatted = $sizeFormatted
                IssueDescription = "Path length $fullPathLen/$maxPathLength chars ($pct% of limit)"
                Suggestion = "Consider shortening - only $($maxPathLength - $fullPathLen) chars remaining"
            })
        }
    }

    # Invalid characters - O(1) HashSet lookup per char
    foreach ($c in $Name.ToCharArray()) {
        if ($script:FastLookup.InvalidCharsSet.Contains($c)) {
            $issues.Add(@{
                Severity = 'Critical'; Issue = 'InvalidCharacters'; Category = 'Invalid Characters'
                Path = $FullPath; Name = $Name; Type = $type
                Size = $FileSize; SizeFormatted = $sizeFormatted
                IssueDescription = "Contains invalid character: $c"
                Suggestion = "Rename to remove '$c'"
            })
            break
        }
    }

    # Reserved names - O(1) HashSet lookup
    $baseName = if ($IsFolder) { $Name } else { [System.IO.Path]::GetFileNameWithoutExtension($Name) }
    if ($script:FastLookup.ReservedNamesSet.Contains($baseName)) {
        $issues.Add(@{
            Severity = 'Critical'; Issue = 'ReservedName'; Category = 'Reserved Names'
            Path = $FullPath; Name = $Name; Type = $type
            Size = $FileSize; SizeFormatted = $sizeFormatted
            IssueDescription = "'$baseName' is a reserved name"
            Suggestion = "Rename to avoid reserved names"
        })
    }

    # Blocked patterns - pre-compiled regex
    if ($script:CompiledPatterns.VtiPattern.IsMatch($Name)) {
        $issues.Add(@{
            Severity = 'Critical'; Issue = 'BlockedPattern'; Category = 'Reserved Names'
            Path = $FullPath; Name = $Name; Type = $type
            Size = $FileSize; SizeFormatted = $sizeFormatted
            IssueDescription = "Contains blocked pattern '_vti_'"
            Suggestion = "Rename to remove '_vti_'"
        })
    }

    # File-specific checks
    if (-not $IsFolder) {
        $ext = [System.IO.Path]::GetExtension($Name).ToLowerInvariant()

        # Blocked extensions - O(1) HashSet lookup
        if ($script:FastLookup.BlockedExtSet.Contains($ext)) {
            $issues.Add(@{
                Severity = 'Warning'; Issue = 'BlockedFileType'; Category = 'Blocked File Types'
                Path = $FullPath; Name = $Name; Type = 'File'
                Size = $FileSize; SizeFormatted = $sizeFormatted
                IssueDescription = "File type '$ext' may be blocked ($sizeFormatted)"
                Suggestion = "Move to non-synced location or request IT to allow"
            })
        }

        # Problematic extensions - O(1) hashtable lookup
        if ($script:FastLookup.ProblematicExtMap.ContainsKey($ext)) {
            $category = $script:FastLookup.ProblematicExtMap[$ext]
            $msg = switch ($category) {
                'CAD' { "CAD files lack file locking - users can overwrite each other" }
                'Adobe' { "Adobe files can't open from cloud, linked files break" }
                'Database' { "Database files may corrupt with multi-user access" }
                'Email' { "PST files sync poorly - locked while Outlook runs" }
                default { "This file type has known SharePoint issues" }
            }
            $issues.Add(@{
                Severity = 'Warning'; Issue = 'ProblematicFile'; Category = $category
                Path = $FullPath; Name = $Name; Type = 'File'
                Size = $FileSize; SizeFormatted = $sizeFormatted
                IssueDescription = "$msg ($sizeFormatted)"
                Suggestion = "Review before migration"
            })
        }

        # File size checks (constants inlined for speed)
        if ($FileSize -gt 268435456000) {  # 250 GB
            $issues.Add(@{
                Severity = 'Critical'; Issue = 'FileTooLarge'; Category = 'File Size'
                Path = $FullPath; Name = $Name; Type = 'File'
                Size = $FileSize; SizeFormatted = $sizeFormatted
                IssueDescription = "File exceeds 250 GB limit ($sizeFormatted)"
                Suggestion = "Split or use alternative storage"
            })
        }
        elseif ($FileSize -gt 10737418240) {  # 10 GB
            $issues.Add(@{
                Severity = 'Warning'; Issue = 'LargeFile'; Category = 'File Size'
                Path = $FullPath; Name = $Name; Type = 'File'
                Size = $FileSize; SizeFormatted = $sizeFormatted
                IssueDescription = "Large file ($sizeFormatted) - will slow sync significantly"
                Suggestion = "Consider archiving or storing outside sync folder"
            })
        }
        elseif ($FileSize -gt 1073741824) {  # 1 GB
            $issues.Add(@{
                Severity = 'Info'; Issue = 'ModerateFile'; Category = 'File Size'
                Path = $FullPath; Name = $Name; Type = 'File'
                Size = $FileSize; SizeFormatted = $sizeFormatted
                IssueDescription = "Moderately large file ($sizeFormatted)"
                Suggestion = "May take time to sync initially"
            })
        }
    }

    # Name conflicts - thread-safe when using ConcurrentDictionary (skip if memory-constrained)
    if (-not $SkipConflictCheck -and $ConflictTracker) {
        $parent = [System.IO.Path]::GetDirectoryName($FullPath)
        $key = "$parent|$($Name.ToLowerInvariant())"
        if ($ConflictTracker.ContainsKey($key)) {
            $issues.Add(@{
                Severity = 'Warning'; Issue = 'NameConflict'; Category = 'Name Conflicts'
                Path = $FullPath; Name = $Name; Type = $type
                Size = $FileSize; SizeFormatted = $sizeFormatted
                IssueDescription = "Conflicts with '$($ConflictTracker[$key])' (case-insensitive)"
                Suggestion = "Rename one item - SharePoint is case-insensitive"
            })
        }
        else {
            $ConflictTracker[$key] = $Name
        }
    }

    # Hidden/System files
    if ($Attributes -band [System.IO.FileAttributes]::Hidden) {
        $issues.Add(@{
            Severity = 'Info'; Issue = 'HiddenItem'; Category = 'Hidden Files'
            Path = $FullPath; Name = $Name; Type = $type
            Size = $FileSize; SizeFormatted = $sizeFormatted
            IssueDescription = "Item is hidden"
            Suggestion = "Verify if migration is intended"
        })
    }
    if ($Attributes -band [System.IO.FileAttributes]::System) {
        $issues.Add(@{
            Severity = 'Info'; Issue = 'SystemItem'; Category = 'System Files'
            Path = $FullPath; Name = $Name; Type = $type
            Size = $FileSize; SizeFormatted = $sizeFormatted
            IssueDescription = "Item is a system file"
            Suggestion = "System files typically should not be migrated"
        })
    }

    return $issues
}

#endregion

#region Report Generation
function New-Report {
    param($Results, [string]$OutputPath, [string]$Format)

    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $baseName = "SP-Readiness_$timestamp"
    $issueCounts = if ($Results.PSObject.Properties.Name -contains 'IssueCounts') { $Results.IssueCounts } else { $null }
    $issueStats = if ($Results.PSObject.Properties.Name -contains 'IssueStats') { $Results.IssueStats } else { $null }
    $issueLogPath = if ($Results.PSObject.Properties.Name -contains 'IssueLogPath') { $Results.IssueLogPath } else { $null }
    $issuesTruncated = if ($Results.PSObject.Properties.Name -contains 'IssuesTruncated') { [bool]$Results.IssuesTruncated } else { $false }
    if ($issueCounts) {
        if ($issueCounts -is [hashtable] -and $issueCounts.ContainsKey('Total')) {
            $totalIssues = [int]$issueCounts['Total']
        } elseif ($issueCounts.PSObject.Properties.Name -contains 'Total') {
            $totalIssues = [int]$issueCounts.Total
        } else {
            $totalIssues = $Results.Issues.Count
        }
    } else {
        $totalIssues = $Results.Issues.Count
    }
    $useLogForIssues = $issueLogPath -and (Test-Path $issueLogPath) -and ($issuesTruncated -or $Results.Issues.Count -lt $totalIssues)

    switch ($Format) {
        'CSV' {
            $path = Join-Path $OutputPath "$baseName.csv"
            if ($useLogForIssues) {
                $writer = [System.IO.StreamWriter]::new($path, $false, [System.Text.Encoding]::UTF8)
                try {
                    $writer.WriteLine("Severity,Issue,Category,Name,Path,IssueDescription,Suggestion")
                    Get-Content -LiteralPath $issueLogPath -ReadCount 1 | ForEach-Object {
                        if ($_) {
                            try {
                                $issueObj = $_ | ConvertFrom-Json
                                $csvLine = ($issueObj | Select-Object Severity, Issue, Category, Name, Path, IssueDescription, Suggestion |
                                    ConvertTo-Csv -NoTypeInformation)[1]
                                $writer.WriteLine($csvLine)
                            } catch { }
                        }
                    }
                } finally {
                    $writer.Dispose()
                }
            } else {
                $Results.Issues | Select-Object Severity, Issue, Category, Name, Path, IssueDescription, Suggestion |
                    Export-Csv -Path $path -NoTypeInformation
            }
            return $path
        }
        'JSON' {
            $path = Join-Path $OutputPath "$baseName.json"
            if ($useLogForIssues) {
                $writer = [System.IO.StreamWriter]::new($path, $false, [System.Text.Encoding]::UTF8)
                try {
                    $props = @($Results.PSObject.Properties | Where-Object { $_.Name -ne 'Issues' })
                    $writer.Write("{")
                    for ($i = 0; $i -lt $props.Count; $i++) {
                        if ($i -gt 0) { $writer.Write(",") }
                        $prop = $props[$i]
                        $writer.Write('"' + $prop.Name + '":')
                        $writer.Write(($prop.Value | ConvertTo-Json -Compress))
                    }
                    if ($props.Count -gt 0) { $writer.Write(",") }
                    $writer.Write('"Issues":[')
                    $firstIssue = $true
                    Get-Content -LiteralPath $issueLogPath -ReadCount 1 | ForEach-Object {
                        if ($_) {
                            if (-not $firstIssue) { $writer.Write(",") } else { $firstIssue = $false }
                            $writer.Write($_)
                        }
                    }
                    $writer.Write("]}")
                } finally {
                    $writer.Dispose()
                }
            } else {
                $Results | ConvertTo-Json -Depth 10 | Out-File $path -Encoding UTF8
            }
            return $path
        }
        'HTML' {
            $path = Join-Path $OutputPath "$baseName.html"

            $critical = if ($issueCounts) {
                if ($issueCounts -is [hashtable]) { [int]$issueCounts['Critical'] } else { [int]$issueCounts.Critical }
            } else {
                ($Results.Issues | Where-Object Severity -eq 'Critical').Count
            }
            $warning = if ($issueCounts) {
                if ($issueCounts -is [hashtable]) { [int]$issueCounts['Warning'] } else { [int]$issueCounts.Warning }
            } else {
                ($Results.Issues | Where-Object Severity -eq 'Warning').Count
            }
            $info = if ($issueCounts) {
                if ($issueCounts -is [hashtable]) { [int]$issueCounts['Info'] } else { [int]$issueCounts.Info }
            } else {
                ($Results.Issues | Where-Object Severity -eq 'Info').Count
            }
            $score = Get-ReadinessScore -Critical $critical -Warning $warning

            $truncated = $totalIssues -gt 500
            $truncateWarning = if ($truncated) { "<div class='truncate-warn'>Showing 500 of $totalIssues issues. Export CSV for complete list.</div>" } else { "" }

            # Generate recommendations
            $recs = Get-MigrationRecommendations -TotalFiles $Results.TotalItems -TotalSize $Results.TotalSize -Issues $Results.Issues -IssueStats $issueStats
            $primaryIcon = switch ($recs.PrimaryIcon) { 'critical' { 'rec-critical' } 'warning' { 'rec-warning' } 'success' { 'rec-success' } default { 'rec-info' } }

            $recDetailsHtml = ""
            foreach ($rec in $recs.Recommendations | Select-Object -First 5) {
                $recClass = switch ($rec.Icon) { 'critical' { 'rec-critical' } 'warning' { 'rec-warning' } default { 'rec-info' } }
                $recDetailsHtml += "<div class='rec-item $recClass'><div class='rec-item-title'>$($rec.Title)</div><div class='rec-item-text'>$($rec.Recommendation)</div><div class='rec-item-detail'>$($rec.Details)</div></div>"
            }

            $accessMethodsHtml = ""
            foreach ($method in $recs.AccessMethods) {
                $verdictClass = switch ($method.Verdict) { 'Recommended' { 'verdict-yes' } 'Not Recommended' { 'verdict-no' } 'Consider' { 'verdict-maybe' } default { 'verdict-neutral' } }
                $accessMethodsHtml += "<tr><td class='method-name'>$($method.Method)</td><td>$($method.BestFor)</td><td>$($method.Avoid)</td><td class='$verdictClass'>$($method.Verdict)</td></tr>"
            }

            # Build Top 10 Largest Files table
            $largestFilesHtml = ""
            if ($Results.LargestFiles -and $Results.LargestFiles.Count -gt 0) {
                $largestFilesHtml = "<div class='rec-section'><h2>Top 10 Largest Files</h2><table class='size-table'><thead><tr><th style='text-align:right'>Size</th><th>File Name</th><th>Path</th></tr></thead><tbody>"
                foreach ($file in $Results.LargestFiles) {
                    $escapedName = [System.Web.HttpUtility]::HtmlEncode($file.Name)
                    $escapedPath = [System.Web.HttpUtility]::HtmlEncode($file.Path)
                    $largestFilesHtml += "<tr><td class='size-val'>$($file.SizeFormatted)</td><td>$escapedName</td><td class='path-val'>$escapedPath</td></tr>"
                }
                $largestFilesHtml += "</tbody></table></div>"
            }

            # Build Top 10 Largest Folders table with expandable file details
            $largestFoldersHtml = ""
            if ($Results.LargestFolders -and $Results.LargestFolders.Count -gt 0) {
                $largestFoldersHtml = "<div class='rec-section'><h2>Top 10 Largest Folders</h2><p class='expand-hint'>Click a folder to see its files</p><table class='size-table folder-table'><thead><tr><th style='text-align:right'>Size</th><th>Folder Path</th><th style='text-align:right'>Files</th></tr></thead><tbody>"
                $folderIdx = 0
                foreach ($folder in $Results.LargestFolders) {
                    $folderIdx++
                    $escapedPath = [System.Web.HttpUtility]::HtmlEncode($folder.Path)
                    $fileCountDisplay = if ($folder.FileCount -gt 0) { "$($folder.FileCount) files" } else { "-" }
                    $hasFiles = $folder.Files -and $folder.Files.Count -gt 0
                    $expandClass = if ($hasFiles) { "expandable" } else { "" }
                    $expandIcon = if ($hasFiles) { "<span class='expand-icon'>+</span>" } else { "" }
                    $largestFoldersHtml += "<tr class='folder-row $expandClass' data-folder='f$folderIdx'>$expandIcon<td class='size-val'>$($folder.SizeFormatted)</td><td class='path-val'>$escapedPath</td><td class='file-count'>$fileCountDisplay</td></tr>"

                    # Add hidden file rows
                    if ($hasFiles) {
                        foreach ($file in $folder.Files) {
                            $escapedFileName = [System.Web.HttpUtility]::HtmlEncode($file.Name)
                            $largestFoldersHtml += "<tr class='file-row hidden' data-parent='f$folderIdx'><td class='size-val file-size'>$($file.SizeFormatted)</td><td class='file-name' colspan='2'>$escapedFileName</td></tr>"
                        }
                        if ($folder.FileCount -gt $folder.Files.Count) {
                            $remaining = $folder.FileCount - $folder.Files.Count
                            $largestFoldersHtml += "<tr class='file-row hidden more-files' data-parent='f$folderIdx'><td></td><td colspan='2'>... and $remaining more files</td></tr>"
                        }
                    }
                }
                $largestFoldersHtml += "</tbody></table></div>"
            }

            $rows = ""
            $issuesForHtml = @()
            if ($Results.Issues -and $Results.Issues.Count -gt 0) {
                $issuesForHtml = $Results.Issues | Select-Object -First 500
            } elseif ($useLogForIssues) {
                $issuesForHtml = Get-Content -LiteralPath $issueLogPath -TotalCount 500 -ReadCount 1 | ForEach-Object {
                    if ($_) {
                        try { $_ | ConvertFrom-Json } catch { }
                    }
                }
            }
            foreach ($issue in $issuesForHtml) {
                if (-not $issue) { continue }
                $sev = $issue.Severity.ToLower()
                $escapedPath = [System.Web.HttpUtility]::HtmlEncode($issue.Path)
                $escapedName = [System.Web.HttpUtility]::HtmlEncode($issue.Name)
                $escapedDesc = [System.Web.HttpUtility]::HtmlEncode($issue.IssueDescription)
                $escapedSugg = [System.Web.HttpUtility]::HtmlEncode($issue.Suggestion)
                $sizeBytes = if ($issue.Size) { $issue.Size } else { 0 }
                $sizeFormatted = if ($issue.SizeFormatted) { $issue.SizeFormatted } else { "-" }
                $rows += "<tr data-sev='$sev' data-size='$sizeBytes'><td><span class='badge $sev'>$($issue.Severity)</span></td><td>$($issue.Issue)</td><td title='$escapedPath'>$escapedName</td><td class='size-cell'>$sizeFormatted</td><td>$escapedDesc</td><td>$escapedSugg</td></tr>`n"
            }

            $html = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SharePoint Readiness Report</title>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Inter:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
:root{--bg-deep:#0d1117;--bg-surface:#161b22;--bg-elevated:#21262d;--border:#30363d;--text:#e6edf3;--text-muted:#8b949e;--accent:#a78bfa;--accent-glow:rgba(167,139,250,0.4);--critical:#f85149;--critical-bg:rgba(248,81,73,0.15);--warning:#d29922;--warning-bg:rgba(210,153,34,0.15);--info:#58a6ff;--info-bg:rgba(88,166,255,0.15);--success:#3fb950}
*{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}
body{font-family:'Inter',system-ui,sans-serif;background:var(--bg-deep);color:var(--text);min-height:100vh;line-height:1.6}
body::before{content:'';position:fixed;inset:0;background:radial-gradient(ellipse at top,rgba(167,139,250,0.08) 0%,transparent 50%),radial-gradient(ellipse at bottom right,rgba(88,166,255,0.05) 0%,transparent 50%);pointer-events:none;z-index:-1}
.container{max-width:1400px;margin:0 auto;padding:40px 24px}
header{text-align:center;margin-bottom:48px;position:relative}
h1{font-family:'JetBrains Mono',monospace;font-size:clamp(1.5rem,4vw,2.5rem);font-weight:600;letter-spacing:-0.02em;margin-bottom:8px;background:linear-gradient(135deg,var(--text) 0%,var(--accent) 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
.subtitle{color:var(--text-muted);font-size:0.9rem;font-weight:400}
.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:32px}
@media(max-width:900px){.cards{grid-template-columns:repeat(2,1fr)}}
@media(max-width:500px){.cards{grid-template-columns:1fr}}
.card{background:var(--bg-surface);border:1px solid var(--border);border-radius:12px;padding:24px;text-align:center;cursor:pointer;transition:all 0.2s ease;position:relative;overflow:hidden}
.card::before{content:'';position:absolute;inset:0;opacity:0;transition:opacity 0.2s}
.card:hover{transform:translateY(-2px);border-color:var(--accent)}
.card:hover::before{opacity:1}
.card.active{border-color:var(--accent);box-shadow:0 0 20px var(--accent-glow)}
.card.score::before{background:linear-gradient(135deg,rgba(63,185,80,0.1) 0%,transparent 100%)}
.card.critical::before{background:linear-gradient(135deg,var(--critical-bg) 0%,transparent 100%)}
.card.warning::before{background:linear-gradient(135deg,var(--warning-bg) 0%,transparent 100%)}
.card.info::before{background:linear-gradient(135deg,var(--info-bg) 0%,transparent 100%)}
.card-label{font-family:'JetBrains Mono',monospace;font-size:0.7rem;text-transform:uppercase;letter-spacing:0.1em;color:var(--text-muted);margin-bottom:8px}
.card-value{font-size:2.5rem;font-weight:300;line-height:1}
.card.score .card-value{color:var(--success)}
.card.critical .card-value{color:var(--critical)}
.card.warning .card-value{color:var(--warning)}
.card.info .card-value{color:var(--info)}
.controls{display:flex;gap:12px;margin-bottom:24px;flex-wrap:wrap;align-items:center}
.search-box{flex:1;min-width:250px;position:relative}
.search-box input{width:100%;background:var(--bg-surface);border:1px solid var(--border);color:var(--text);padding:12px 16px 12px 44px;border-radius:8px;font-size:0.95rem;transition:all 0.2s}
.search-box input:focus{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px var(--accent-glow)}
.search-box input::placeholder{color:var(--text-muted)}
.search-box svg{position:absolute;left:14px;top:50%;transform:translateY(-50%);color:var(--text-muted);width:18px;height:18px}
.clear-filter{background:var(--bg-elevated);border:1px solid var(--border);color:var(--text-muted);padding:12px 20px;border-radius:8px;font-size:0.85rem;cursor:pointer;transition:all 0.2s;font-family:'JetBrains Mono',monospace}
.clear-filter:hover{border-color:var(--accent);color:var(--text)}
.truncate-warn{background:var(--warning-bg);border:1px solid var(--warning);color:var(--warning);padding:12px 16px;border-radius:8px;margin-bottom:16px;font-size:0.85rem;display:flex;align-items:center;gap:8px}
.truncate-warn::before{content:'!';width:20px;height:20px;background:var(--warning);color:var(--bg-deep);border-radius:50%;display:flex;align-items:center;justify-content:center;font-weight:600;font-size:0.75rem;flex-shrink:0}
.table-wrap{background:var(--bg-surface);border:1px solid var(--border);border-radius:12px;overflow:hidden}
table{width:100%;border-collapse:collapse}
th{font-family:'JetBrains Mono',monospace;font-size:0.7rem;text-transform:uppercase;letter-spacing:0.08em;color:var(--text-muted);font-weight:600;padding:16px 20px;text-align:left;background:var(--bg-elevated);border-bottom:1px solid var(--border);cursor:pointer;user-select:none;white-space:nowrap;transition:color 0.2s}
th:hover{color:var(--accent)}
th span{display:inline-flex;align-items:center;gap:6px}
th .sort-icon{opacity:0.3;transition:opacity 0.2s}
th.sorted .sort-icon{opacity:1;color:var(--accent)}
td{padding:14px 20px;border-bottom:1px solid var(--border);font-size:0.9rem;vertical-align:top}
tr:last-child td{border-bottom:none}
tr:hover td{background:rgba(167,139,250,0.03)}
tr.hidden{display:none}
.badge{display:inline-flex;align-items:center;gap:6px;padding:5px 12px;border-radius:6px;font-family:'JetBrains Mono',monospace;font-size:0.7rem;font-weight:600;text-transform:uppercase;letter-spacing:0.05em}
.badge::before{content:'';width:6px;height:6px;border-radius:50%;flex-shrink:0}
.badge.critical{background:var(--critical-bg);color:var(--critical)}.badge.critical::before{background:var(--critical)}
.badge.warning{background:var(--warning-bg);color:var(--warning)}.badge.warning::before{background:var(--warning)}
.badge.info{background:var(--info-bg);color:var(--info)}.badge.info::before{background:var(--info)}
.name-cell{font-family:'JetBrains Mono',monospace;font-size:0.85rem;color:var(--accent);max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.desc-cell{color:var(--text-muted);max-width:300px}
.sugg-cell{color:var(--text);font-size:0.85rem;max-width:250px}
.size-cell{font-family:'JetBrains Mono',monospace;font-size:0.85rem;color:var(--text-muted);text-align:right;white-space:nowrap}
.size-col{text-align:right}
.size-table{width:100%;border-collapse:collapse;font-size:0.85rem;margin-bottom:24px}
.size-table th{text-align:left;padding:10px 12px;background:var(--bg-deep);color:var(--text-muted);font-family:'JetBrains Mono',monospace;font-size:0.7rem;text-transform:uppercase;letter-spacing:0.05em}
.size-table td{padding:10px 12px;border-bottom:1px solid var(--border)}
.size-table td.size-val{font-family:'JetBrains Mono',monospace;color:var(--accent);text-align:right;white-space:nowrap;width:100px}
.size-table td.path-val{color:var(--text);word-break:break-all;font-size:0.85rem}
.size-table tr:hover td{background:rgba(167,139,250,0.03)}
.expand-hint{color:var(--text-muted);font-size:0.8rem;margin-bottom:12px;font-style:italic}
.folder-table .folder-row{position:relative}
.folder-table .folder-row.expandable{cursor:pointer}
.folder-table .folder-row.expandable:hover td{background:rgba(167,139,250,0.08)}
.expand-icon{position:absolute;left:8px;top:50%;transform:translateY(-50%);color:var(--accent);font-family:'JetBrains Mono',monospace;font-weight:bold;font-size:0.9rem;width:16px;text-align:center;transition:transform 0.2s}
.folder-row.expanded .expand-icon{transform:translateY(-50%) rotate(45deg)}
.file-row{background:var(--bg-elevated)}
.file-row td{padding:6px 12px 6px 32px;font-size:0.8rem;border-bottom:1px solid rgba(48,54,61,0.5)}
.file-row .file-size{color:var(--text-muted);font-size:0.75rem}
.file-row .file-name{color:var(--text-muted);font-family:'JetBrains Mono',monospace;font-size:0.8rem}
.file-row.more-files td{color:var(--text-muted);font-style:italic;font-size:0.75rem}
.file-row.hidden{display:none}
.file-count{color:var(--text-muted);font-size:0.8rem;text-align:right}
footer{text-align:center;padding:48px 24px;color:var(--text-muted);font-size:0.8rem;border-top:1px solid var(--border);margin-top:48px}
footer a{color:var(--accent);text-decoration:none}
.empty-state{text-align:center;padding:60px 20px;color:var(--text-muted)}
.empty-state svg{width:48px;height:48px;margin-bottom:16px;opacity:0.5}
.rec-section{background:var(--bg-surface);border:1px solid var(--border);border-radius:12px;padding:24px;margin-bottom:32px}
.rec-section h2{font-family:'JetBrains Mono',monospace;font-size:0.8rem;text-transform:uppercase;letter-spacing:0.1em;color:var(--text-muted);margin-bottom:20px;display:flex;align-items:center;gap:8px}
.rec-section h2::before{content:'';width:4px;height:16px;background:var(--accent);border-radius:2px}
.rec-primary{background:var(--bg-elevated);border-radius:8px;padding:20px;margin-bottom:20px;border-left:4px solid var(--accent)}
.rec-primary.rec-critical{border-left-color:var(--critical);background:var(--critical-bg)}
.rec-primary.rec-warning{border-left-color:var(--warning);background:var(--warning-bg)}
.rec-primary.rec-success{border-left-color:var(--success);background:rgba(63,185,80,0.1)}
.rec-primary-title{font-size:1.1rem;font-weight:600;margin-bottom:8px}
.rec-primary-reason{color:var(--text-muted);font-size:0.9rem;line-height:1.5}
.rec-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px;margin-bottom:24px}
.rec-item{background:var(--bg-elevated);border-radius:8px;padding:16px;border-left:3px solid var(--border)}
.rec-item.rec-critical{border-left-color:var(--critical)}
.rec-item.rec-warning{border-left-color:var(--warning)}
.rec-item.rec-info{border-left-color:var(--info)}
.rec-item-title{font-weight:600;font-size:0.9rem;margin-bottom:6px}
.rec-item-text{color:var(--accent);font-size:0.85rem;margin-bottom:8px}
.rec-item-detail{color:var(--text-muted);font-size:0.8rem;line-height:1.5}
.access-table{width:100%;border-collapse:collapse;font-size:0.85rem}
.access-table th{text-align:left;padding:12px;background:var(--bg-deep);color:var(--text-muted);font-family:'JetBrains Mono',monospace;font-size:0.7rem;text-transform:uppercase;letter-spacing:0.05em}
.access-table td{padding:12px;border-bottom:1px solid var(--border)}
.access-table .method-name{font-weight:600;color:var(--text);white-space:nowrap}
.verdict-yes{color:var(--success);font-weight:600}
.verdict-no{color:var(--critical);font-weight:600}
.verdict-maybe{color:var(--warning);font-weight:600}
.verdict-neutral{color:var(--text-muted)}
.section-title{font-family:'JetBrains Mono',monospace;font-size:0.75rem;text-transform:uppercase;letter-spacing:0.1em;color:var(--text-muted);margin:24px 0 16px;padding-bottom:8px;border-bottom:1px solid var(--border)}
@media(max-width:768px){td,th{padding:12px 14px;font-size:0.8rem}.badge{padding:4px 8px;font-size:0.65rem}.rec-grid{grid-template-columns:1fr}}
</style></head>
<body>
<div class="container">
<header>
<h1>SharePoint Readiness Report</h1>
<p class="subtitle">Migration compatibility analysis for $($Results.SourcePath)</p>
</header>
<div class="cards">
<div class="card score" onclick="filterBySev('all')"><div class="card-label">Readiness</div><div class="card-value">$([int]$score)%</div></div>
<div class="card critical" onclick="filterBySev('critical')"><div class="card-label">Critical</div><div class="card-value">$critical</div></div>
<div class="card warning" onclick="filterBySev('warning')"><div class="card-label">Warnings</div><div class="card-value">$warning</div></div>
<div class="card info" onclick="filterBySev('info')"><div class="card-label">Info</div><div class="card-value">$info</div></div>
</div>
<div class="rec-section">
<h2>Migration Recommendations</h2>
<div class="rec-primary $primaryIcon">
<div class="rec-primary-title">$($recs.PrimaryRecommendation)</div>
<div class="rec-primary-reason">$($recs.PrimaryReason)</div>
</div>
<div class="rec-grid">$recDetailsHtml</div>
<div class="section-title">Access Method Comparison</div>
<table class="access-table">
<thead><tr><th>Method</th><th>Best For</th><th>Avoid When</th><th>Verdict</th></tr></thead>
<tbody>$accessMethodsHtml</tbody>
</table>
</div>
$largestFilesHtml
$largestFoldersHtml
<div class="controls">
<div class="search-box">
<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
<input type="text" id="search" placeholder="Search issues..." oninput="searchFilter()">
</div>
<button class="clear-filter" onclick="clearFilters()">Clear Filters</button>
</div>
$truncateWarning
<div class="table-wrap">
<table id="t">
<thead><tr>
<th onclick="sortTable(0)"><span>Severity<svg class="sort-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M7 10l5-5 5 5M7 14l5 5 5-5"/></svg></span></th>
<th onclick="sortTable(1)"><span>Issue<svg class="sort-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M7 10l5-5 5 5M7 14l5 5 5-5"/></svg></span></th>
<th onclick="sortTable(2)"><span>Name<svg class="sort-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M7 10l5-5 5 5M7 14l5 5 5-5"/></svg></span></th>
<th onclick="sortTable(3)" class="size-col"><span>Size<svg class="sort-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M7 10l5-5 5 5M7 14l5 5 5-5"/></svg></span></th>
<th onclick="sortTable(4)"><span>Description<svg class="sort-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M7 10l5-5 5 5M7 14l5 5 5-5"/></svg></span></th>
<th onclick="sortTable(5)"><span>Suggestion<svg class="sort-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M7 10l5-5 5 5M7 14l5 5 5-5"/></svg></span></th>
</tr></thead>
<tbody>$rows</tbody>
</table>
</div>
<footer>Generated by <a href="https://github.com/ajoshuasmith/SharePoint-Prescan">SharePoint-Readiness Scanner</a> on $(Get-Date -Format 'yyyy-MM-dd') at $(Get-Date -Format 'HH:mm')</footer>
</div>
<script>
let currentSev='all',sortCol=-1,sortAsc=true;
const rows=()=>Array.from(document.querySelectorAll('#t tbody tr'));
const cards=document.querySelectorAll('.card');
function filterBySev(sev){
currentSev=sev;
cards.forEach(c=>{c.classList.remove('active');if((sev==='all'&&c.classList.contains('score'))||c.classList.contains(sev))c.classList.add('active')});
applyFilters();
}
function searchFilter(){applyFilters()}
function applyFilters(){
const q=document.getElementById('search').value.toLowerCase();
rows().forEach(r=>{
const matchSev=currentSev==='all'||r.dataset.sev===currentSev;
const matchSearch=!q||r.textContent.toLowerCase().includes(q);
r.classList.toggle('hidden',!(matchSev&&matchSearch));
});
}
function clearFilters(){
document.getElementById('search').value='';
currentSev='all';
cards.forEach(c=>c.classList.remove('active'));
document.querySelector('.card.score').classList.add('active');
rows().forEach(r=>r.classList.remove('hidden'));
document.querySelectorAll('th').forEach(h=>h.classList.remove('sorted'));
}
function sortTable(n){
const tbody=document.querySelector('#t tbody');
const th=document.querySelectorAll('th');
if(sortCol===n)sortAsc=!sortAsc;else{sortCol=n;sortAsc=true}
th.forEach((h,i)=>h.classList.toggle('sorted',i===n));
const sorted=rows().sort((a,b)=>{
let av=a.cells[n].textContent.trim(),bv=b.cells[n].textContent.trim();
if(n===0){const ord={critical:0,warning:1,info:2};av=ord[a.dataset.sev];bv=ord[b.dataset.sev];return sortAsc?av-bv:bv-av}
if(n===3){av=parseInt(a.dataset.size||0);bv=parseInt(b.dataset.size||0);return sortAsc?av-bv:bv-av}
return sortAsc?av.localeCompare(bv):bv.localeCompare(av);
});
sorted.forEach(r=>tbody.appendChild(r));
}
// Folder expansion toggle
document.querySelectorAll('.folder-row.expandable').forEach(row=>{
row.addEventListener('click',()=>{
const folderId=row.dataset.folder;
const isExpanded=row.classList.toggle('expanded');
document.querySelectorAll('.file-row[data-parent="'+folderId+'"]').forEach(fr=>{
fr.classList.toggle('hidden',!isExpanded);
});
});
});
document.querySelector('.card.score').classList.add('active');
</script>
</body></html>
"@
            $html | Out-File $path -Encoding UTF8
            return $path
        }
    }
}
#endregion

#region Main
Write-Banner

# Interactive mode if no path provided
if (-not $Path) {
    $Path = Read-Input -Prompt "Source path to scan" -Required -IsPath
}

if (-not $DestinationUrl) {
    Write-Host ""
    Write-Host "    $($script:UI.Bullet) " -NoNewline -ForegroundColor Cyan
    Write-Host "Enter the SharePoint document library URL where files will be migrated" -ForegroundColor Gray
    Write-Host "      Example: " -NoNewline -ForegroundColor DarkGray
    Write-Host "https://contoso.sharepoint.com/sites/management/Shared%20Documents" -ForegroundColor White
    Write-Host ""
    $DestinationUrl = Read-Input -Prompt "SharePoint destination URL" -Required -IsUrl
}

# Normalize SharePoint URL - strip view URLs like /Forms/AllItems.aspx
$normalizedUrl = $DestinationUrl -replace '/Forms/[^/]+\.aspx$', '' -replace '/_layouts/.*$', ''
if ($normalizedUrl -ne $DestinationUrl) {
    Write-Host ""
    Write-Host "    $($script:UI.Bullet) " -NoNewline -ForegroundColor Yellow
    Write-Host "Normalized URL (removed SharePoint view path)" -ForegroundColor Gray
    $DestinationUrl = $normalizedUrl
}

# Calculate destination path length
$destUri = [System.Uri]::new($DestinationUrl)
$destPathLength = $destUri.AbsolutePath.Length

Write-Host ""
Write-Divider
Write-Host ""
Write-Info -Label "Destination URL: " -Value $DestinationUrl
Write-Info -Label "Base path uses: " -Value "$destPathLength of $($script:MaxPathLength) characters"

# Ask about additional subfolder
# Extract library name from URL for clearer prompt
$libraryName = ($destUri.AbsolutePath -split '/')[-1] -replace '%20', ' '
if ([string]::IsNullOrEmpty($libraryName)) { $libraryName = "Documents" }

Write-Host ""
Write-Host "    $($script:UI.Bullet) " -NoNewline -ForegroundColor Cyan
Write-Host "Will files be placed in a subfolder under '$libraryName'?" -ForegroundColor Gray
Write-Host "      Example: If migrating to $libraryName/Clients/Acme, enter: " -NoNewline -ForegroundColor DarkGray
Write-Host "Clients/Acme" -ForegroundColor White
$subfolder = Read-Host "    Subfolder path (press Enter if uploading to root of $libraryName)"
$subfolderLength = 0
if (-not [string]::IsNullOrWhiteSpace($subfolder)) {
    # Normalize subfolder: ensure leading slash, remove trailing slash
    $subfolder = $subfolder.TrimStart('/').TrimEnd('/')
    $subfolderLength = $subfolder.Length + 1  # +1 for the leading slash
    $destPathLength += $subfolderLength
    Write-Host "    $($script:UI.Check) " -NoNewline -ForegroundColor Green
    Write-Host "Added /$subfolder ($subfolderLength chars)" -ForegroundColor Gray
}

Write-Host ""
Write-Info -Label "Total destination path: " -Value "$destPathLength of $($script:MaxPathLength) characters"
Write-Info -Label "Available for files: " -Value "$($script:MaxPathLength - $destPathLength) characters" -ValueColor Green
Write-Host ""
Write-Divider
Write-Host ""

# Set output path
if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-Location) "SP-Readiness-Reports"
}
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$robocopyCmd = Get-Command robocopy -ErrorAction SilentlyContinue
if (-not $robocopyCmd) {
    throw "Robocopy is required but was not found in PATH."
}

# Initialize checkpoint system
Initialize-CheckpointSystem -SourcePath $Path -OutputDir $OutputPath | Out-Null
$robocopyLogPath = $script:RobocopyLogPath
$robocopyStartLine = 0
$robocopyRebuildLog = $false

# Check for existing checkpoint if Resume requested
$resumeCheckpoint = $null
$scannedDirsSet = [System.Collections.Concurrent.ConcurrentDictionary[string, bool]]::new()
$resumedFromCheckpoint = $false

if ($Resume) {
    $resumeCheckpoint = Get-ExistingCheckpoint -SourcePath $Path -DestinationUrl $DestinationUrl
    if ($resumeCheckpoint) {
        $hasRobocopyState = ($resumeCheckpoint.PSObject.Properties.Name -contains 'RobocopyLogPath') -and ($resumeCheckpoint.PSObject.Properties.Name -contains 'RobocopyLine')
        if (-not $hasRobocopyState) {
            Write-Host ""
            Write-Host "    ! Checkpoint missing robocopy state. Resume not possible." -ForegroundColor Yellow
            $resumeCheckpoint = $null
            $robocopyLogPath = $script:RobocopyLogPath
            $robocopyStartLine = 0
        }
        else {
        if ($resumeCheckpoint.RobocopyLogPath) {
            $robocopyLogPath = $resumeCheckpoint.RobocopyLogPath
        }
        if ($resumeCheckpoint.RobocopyLine) {
            $robocopyStartLine = [int]$resumeCheckpoint.RobocopyLine
        }
        if (-not $robocopyLogPath -or -not (Test-Path $robocopyLogPath)) {
            Write-Host ""
            Write-Host "    ! Robocopy log not found. Resume not possible." -ForegroundColor Yellow
            $resumeCheckpoint = $null
            $robocopyLogPath = $script:RobocopyLogPath
            $robocopyStartLine = 0
        }
        else {
        Write-Host ""
        Write-Host "    $($script:UI.Check) " -NoNewline -ForegroundColor Green
        Write-Host "Found checkpoint from " -NoNewline -ForegroundColor Gray
        Write-Host $resumeCheckpoint.Timestamp -ForegroundColor Cyan
        Write-Host "    $($script:UI.Bullet) " -NoNewline -ForegroundColor Cyan
        Write-Host "Previously scanned: " -NoNewline -ForegroundColor Gray
        Write-Host ("{0:N0}" -f $resumeCheckpoint.ItemCount) -NoNewline -ForegroundColor Yellow
        Write-Host " items, " -NoNewline -ForegroundColor Gray
        Write-Host ("{0:N0}" -f $resumeCheckpoint.ScannedDirs.Count) -NoNewline -ForegroundColor Yellow
        Write-Host " directories" -ForegroundColor Gray

        # Load scanned directories into set
        foreach ($dir in $resumeCheckpoint.ScannedDirs) {
            $scannedDirsSet.TryAdd($dir, $true) | Out-Null
        }
        $resumedFromCheckpoint = $true
        if ($robocopyStartLine -gt 0) {
            Write-Host "    $($script:UI.Bullet) " -NoNewline -ForegroundColor Cyan
            Write-Host "Resuming robocopy log at line " -NoNewline -ForegroundColor Gray
            Write-Host ("{0:N0}" -f $robocopyStartLine) -ForegroundColor Yellow
        }
        $robocopyComplete = $false
        if ($resumeCheckpoint.PSObject.Properties.Name -contains 'RobocopyComplete') {
            $robocopyComplete = [bool]$resumeCheckpoint.RobocopyComplete
        }
        if ($robocopyComplete -and $robocopyLogPath -and (Test-Path $robocopyLogPath)) {
            $logMismatch = $false
            $logInfo = Get-Item -LiteralPath $robocopyLogPath -ErrorAction SilentlyContinue
            if ($logInfo) {
                if ($resumeCheckpoint.PSObject.Properties.Name -contains 'RobocopyLogSize') {
                    if ([long]$resumeCheckpoint.RobocopyLogSize -ne $logInfo.Length) {
                        $logMismatch = $true
                    }
                }
                if (-not $logMismatch -and ($resumeCheckpoint.PSObject.Properties.Name -contains 'RobocopyLogLastWriteUtc')) {
                    try {
                        $expectedWrite = [DateTime]::Parse($resumeCheckpoint.RobocopyLogLastWriteUtc).ToUniversalTime()
                        if ($expectedWrite -ne $logInfo.LastWriteTimeUtc) {
                            $logMismatch = $true
                        }
                    } catch {
                        $logMismatch = $true
                    }
                }
            }
            if ($logMismatch) {
                Write-Host "    ! Robocopy log does not match checkpoint. Starting fresh scan." -ForegroundColor Yellow
                $resumeCheckpoint = $null
                $resumedFromCheckpoint = $false
                $scannedDirsSet.Clear()
                $robocopyLogPath = $script:RobocopyLogPath
                $robocopyStartLine = 0
                $robocopyRebuildLog = $false
            }
        }
        if (-not $robocopyComplete) {
            $robocopyRebuildLog = $true
            Write-Host "    ! Previous robocopy log is incomplete. Rebuilding log and resuming from saved line." -ForegroundColor Yellow
        }
        Write-Host ""
        }
        }
    } else {
        Write-Host ""
        Write-Host "    ! No checkpoint found, starting fresh scan" -ForegroundColor Yellow
        Write-Host ""
    }
} elseif (Test-Path $script:CheckpointPath) {
    # Existing checkpoint but no -Resume flag - warn user
    $existingCp = Get-ExistingCheckpoint -SourcePath $Path -DestinationUrl $DestinationUrl
    if ($existingCp) {
        Write-Host ""
        Write-Host "    ! " -NoNewline -ForegroundColor Yellow
        Write-Host "Found previous incomplete scan from $($existingCp.Timestamp)" -ForegroundColor Yellow
        Write-Host "      Use " -NoNewline -ForegroundColor DarkGray
        Write-Host "-Resume" -NoNewline -ForegroundColor Cyan
        Write-Host " to continue, or this scan will start fresh" -ForegroundColor DarkGray
        Write-Host ""
    }
}

# Clear incremental issues file for fresh scan (or keep for resume)
if (-not $resumedFromCheckpoint -and (Test-Path $script:IncrementalPath)) {
    Remove-Item $script:IncrementalPath -Force -ErrorAction SilentlyContinue
}
if (-not $resumedFromCheckpoint -and $script:RobocopyLogPath -and (Test-Path $script:RobocopyLogPath)) {
    Remove-Item $script:RobocopyLogPath -Force -ErrorAction SilentlyContinue
}
if ($robocopyRebuildLog -and $robocopyLogPath -and (Test-Path $robocopyLogPath)) {
    Remove-Item $robocopyLogPath -Force -ErrorAction SilentlyContinue
}

# Scan header
Write-Step -Message "Starting scan..." -Status 'Running'
Write-Host ""
Write-Info -Label "Source: " -Value $Path
Write-Info -Label "Destination: " -Value $DestinationUrl
Write-Host ""

$scanStart = Get-Date
$Path = $Path.TrimEnd('\', '/')
$pathLen = $Path.Length

# Shared collections for scan results
$allIssues = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()
$conflictTracker = [System.Collections.Concurrent.ConcurrentDictionary[string, string]]::new()
$folderSizes = [System.Collections.Concurrent.ConcurrentDictionary[string, long]]::new()
$folderFiles = [System.Collections.Concurrent.ConcurrentDictionary[string, System.Collections.Concurrent.ConcurrentBag[hashtable]]]::new()
$folderFileCounts = [System.Collections.Concurrent.ConcurrentDictionary[string, int]]::new()

# Thread-safe counters (initialize from checkpoint if resuming)
$itemCount = [ref]0
$fileCount = [ref]0
$folderCount = [ref]0
$totalSize = [ref]0L
$issueCounts = @{
    Critical = 0
    Warning = 0
    Info = 0
    Total = 0
}
$issueStats = @{
    CAD = 0
    Adobe = 0
    Database = 0
    Email = 0
    PathIssues = 0
}
$issuesInMemoryCount = [ref]0
$issuesInMemoryTruncated = $false
$issuesTruncatedRef = [ref]$issuesInMemoryTruncated

# Restore state from checkpoint if resuming
if ($resumedFromCheckpoint -and $resumeCheckpoint) {
    $itemCount.Value = $resumeCheckpoint.ItemCount
    $fileCount.Value = $resumeCheckpoint.FileCount
    $folderCount.Value = $resumeCheckpoint.FolderCount
    $totalSize.Value = $resumeCheckpoint.TotalSize

    # Restore folder sizes
    if ($resumeCheckpoint.FolderSizes) {
        foreach ($key in $resumeCheckpoint.FolderSizes.PSObject.Properties.Name) {
            $folderSizes.TryAdd($key, [long]$resumeCheckpoint.FolderSizes.$key) | Out-Null
        }
    }

    # Restore folder file counts
    if ($resumeCheckpoint.FolderFileCounts) {
        foreach ($key in $resumeCheckpoint.FolderFileCounts.PSObject.Properties.Name) {
            $folderFileCounts.TryAdd($key, [int]$resumeCheckpoint.FolderFileCounts.$key) | Out-Null
        }
    }

    $hasIssueCounts = $false
    if ($resumeCheckpoint.PSObject.Properties.Name -contains 'IssueCounts') {
        $issueCounts = @{
            Critical = [int]$resumeCheckpoint.IssueCounts.Critical
            Warning = [int]$resumeCheckpoint.IssueCounts.Warning
            Info = [int]$resumeCheckpoint.IssueCounts.Info
            Total = [int]$resumeCheckpoint.IssueCounts.Total
        }
        $hasIssueCounts = $true
    }
    $hasIssueStats = $false
    if ($resumeCheckpoint.PSObject.Properties.Name -contains 'IssueStats') {
        $issueStats = @{
            CAD = [int]$resumeCheckpoint.IssueStats.CAD
            Adobe = [int]$resumeCheckpoint.IssueStats.Adobe
            Database = [int]$resumeCheckpoint.IssueStats.Database
            Email = [int]$resumeCheckpoint.IssueStats.Email
            PathIssues = [int]$resumeCheckpoint.IssueStats.PathIssues
        }
        $hasIssueStats = $true
    }
    if (-not $hasIssueCounts -and $hasIssueStats) {
        $issueStats = @{
            CAD = 0
            Adobe = 0
            Database = 0
            Email = 0
            PathIssues = 0
        }
        $hasIssueStats = $false
    }

    # Load previously found issues from incremental file (for reports and/or missing stats)
    if (Test-Path $script:IncrementalPath) {
        $loadAllIssues = (-not $hasIssueCounts) -or (-not $hasIssueStats) -or ($MaxIssuesInMemory -le 0)
        $contentParams = @{
            LiteralPath = $script:IncrementalPath
            ReadCount = 1
        }
        if (-not $loadAllIssues -and $MaxIssuesInMemory -gt 0) {
            $contentParams.TotalCount = $MaxIssuesInMemory
        }

        Get-Content @contentParams -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_) {
                try {
                    $issue = $_ | ConvertFrom-Json
                    $ht = @{}
                    $issue.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }

                    if (-not $hasIssueCounts) {
                        Update-IssueAggregates -Issue $ht -IssueCounts $issueCounts -IssueStats $issueStats
                    } elseif (-not $hasIssueStats) {
                        switch ($ht.Category) {
                            'CAD' { $issueStats.CAD++ }
                            'Adobe' { $issueStats.Adobe++ }
                            'Database' { $issueStats.Database++ }
                            'Email' { $issueStats.Email++ }
                        }
                        if ($ht.Issue -eq 'PathTooLong' -or $ht.Issue -eq 'PathNearLimit') {
                            $issueStats.PathIssues++
                        }
                    }

                    if ($MaxIssuesInMemory -le 0 -or $issuesInMemoryCount.Value -lt $MaxIssuesInMemory) {
                        $allIssues.Add($ht)
                        $issuesInMemoryCount.Value++
                    } else {
                        $issuesInMemoryTruncated = $true
                    }
                } catch { }
            }
        }

        if ($issueCounts.Total -gt 0 -and $issuesInMemoryCount.Value -lt $issueCounts.Total) {
            $issuesInMemoryTruncated = $true
        }

        $loadedMsg = $issuesInMemoryCount.Value
        $totalMsg = if ($issueCounts.Total -gt 0) { $issueCounts.Total } else { $loadedMsg }
        Write-Host "    $($script:UI.Bullet) " -NoNewline -ForegroundColor Cyan
        Write-Host "Loaded " -NoNewline -ForegroundColor Gray
        Write-Host ("{0:N0}" -f $loadedMsg) -NoNewline -ForegroundColor Yellow
        if ($loadedMsg -lt $totalMsg) {
            Write-Host " of " -NoNewline -ForegroundColor Gray
            Write-Host ("{0:N0}" -f $totalMsg) -NoNewline -ForegroundColor Yellow
        }
        Write-Host " issues from previous scan" -ForegroundColor Gray
    }
}

# Top 10 largest files
$top10Files = [System.Collections.Generic.List[hashtable]]::new()
$minTop10Size = [ref]0L

# Memory-aware configuration
$availableMemoryGB = 0
$skipConflictCheck = $false

# Get available memory (cross-platform)
try {
    if ($IsWindows -or $env:OS -match 'Windows') {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) { $availableMemoryGB = [Math]::Round($os.FreePhysicalMemory / 1MB, 1) }
    } else {
        # macOS/Linux - read from /proc or vm_stat
        if (Test-Path '/proc/meminfo') {
            $memFree = (Get-Content '/proc/meminfo' | Where-Object { $_ -match '^MemAvailable' }) -replace '[^0-9]', ''
            if ($memFree) { $availableMemoryGB = [Math]::Round([long]$memFree / 1MB, 1) }
        } else {
            # macOS fallback
            $vmStat = vm_stat 2>$null
            if ($vmStat) {
                $pageSize = 4096
                $freePages = [long](($vmStat | Where-Object { $_ -match 'Pages free' }) -replace '[^0-9]', '')
                $availableMemoryGB = [Math]::Round(($freePages * $pageSize) / 1GB, 1)
            }
        }
    }
} catch { $availableMemoryGB = 4 }  # Conservative default if detection fails

# Adaptive settings based on available memory
if ($availableMemoryGB -lt 2) {
    $skipConflictCheck = $true
    Write-Host "    Low Memory Mode: " -NoNewline -ForegroundColor Yellow
    Write-Host "$availableMemoryGB GB available - conflict check disabled" -ForegroundColor Gray
} elseif ($availableMemoryGB -lt 4) {
    $skipConflictCheck = $true
    Write-Host "    Limited Memory Mode: " -NoNewline -ForegroundColor Yellow
    Write-Host "$availableMemoryGB GB available - conflict check disabled" -ForegroundColor Gray
} elseif ($availableMemoryGB -lt 8) {
    Write-Host "    Standard Mode: " -NoNewline -ForegroundColor Cyan
    Write-Host "$availableMemoryGB GB available - conflict check enabled" -ForegroundColor Gray
} else {
    Write-Host "    High Memory Mode: " -NoNewline -ForegroundColor Green
    Write-Host "$availableMemoryGB GB available - conflict check enabled" -ForegroundColor Gray
}
Write-Host ""

if ($FastAttributes) {
    Write-Host "    Fast Attributes Mode: " -NoNewline -ForegroundColor Yellow
    Write-Host "Hidden/System checks disabled for speed" -ForegroundColor Gray
    Write-Host ""
}

if ($MaxIssuesInMemory -gt 0) {
    Write-Host "    Issue Memory Cap: " -NoNewline -ForegroundColor Cyan
    Write-Host ("{0:N0} issues (full log saved to disk)" -f $MaxIssuesInMemory) -ForegroundColor Gray
    Write-Host ""
}

# Robocopy enumeration (Windows-only).
Write-Host "    Robocopy Mode: list-only enumeration" -ForegroundColor Cyan
Write-Host ""

# Progress reporting timer
$progressTimer = [System.Diagnostics.Stopwatch]::StartNew()
$spinnerChars = @('|', '/', '-', '\')
$spinnerIndex = 0
$lastCheckpointItems = 0
$robocopyLineNumber = $robocopyStartLine
$robocopyComplete = $false

# Process root folder
$itemCount.Value++
$folderCount.Value++
$tracker = if ($skipConflictCheck) { $null } else { $conflictTracker }
$rootAttributes = [System.IO.FileAttributes]::Directory
if (-not $FastAttributes) {
    try { $rootAttributes = (Get-Item -LiteralPath $Path -ErrorAction Stop).Attributes } catch { }
}
$rootIssues = Test-ItemFast -FullPath $Path -Name (Split-Path $Path -Leaf) -IsFolder $true -FileSize 0 `
    -Attributes $rootAttributes -RelativePath "" -DestPathLength $destPathLength -WarningThresholdPercent $WarningThreshold `
    -ConflictTracker $tracker -SkipConflictCheck $skipConflictCheck
foreach ($issue in $rootIssues) {
    Add-IssueRecord -Issue $issue -IssueBag $allIssues -IssueCounts $issueCounts -IssueStats $issueStats `
        -MaxIssuesInMemory $MaxIssuesInMemory -IssuesInMemoryCount $issuesInMemoryCount -IssuesTruncated $issuesTruncatedRef
}
$folderSizes.TryAdd($Path, 0L) | Out-Null
$folderFileCounts.TryAdd($Path, 0) | Out-Null
if (-not $folderFiles.ContainsKey($Path)) { $folderFiles.TryAdd($Path, [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()) | Out-Null }
$scannedDirsSet.TryAdd($Path, $true) | Out-Null

foreach ($entry in Get-RobocopyItems -SourcePath $Path -ExcludeDirs $ExcludeDirs -LogPath $robocopyLogPath -StartLine $robocopyStartLine -LineCounter ([ref]$robocopyLineNumber)) {
    if (-not $entry.FullPath) { continue }

    $fullPath = $entry.FullPath.TrimEnd('\', '/')
    if (-not $fullPath -or $fullPath -eq $Path -or $fullPath.Length -lt $pathLen) { continue }
    $isDir = [bool]$entry.IsDirectory
    $size = [long]$entry.Size
    $name = Split-Path $fullPath -Leaf
    $relativePath = $fullPath.Substring($pathLen).TrimStart('\', '/')

    if ($FastAttributes) {
        $attributes = if ($isDir) { [System.IO.FileAttributes]::Directory } else { [System.IO.FileAttributes]::Normal }
    } else {
        $attributes = [System.IO.FileAttributes]::Normal
        try { $attributes = (Get-Item -LiteralPath $fullPath -ErrorAction Stop).Attributes } catch { }
    }

    $itemCount.Value++
    if ($isDir) {
        $folderCount.Value++
        $folderSizes.TryAdd($fullPath, 0L) | Out-Null
        $folderFileCounts.TryAdd($fullPath, 0) | Out-Null
        $scannedDirsSet.TryAdd($fullPath, $true) | Out-Null
    } else {
        $fileCount.Value++
        $totalSize.Value += $size
    }

    $issues = Test-ItemFast -FullPath $fullPath -Name $name -IsFolder $isDir -FileSize $size `
        -Attributes $attributes -RelativePath $relativePath -DestPathLength $destPathLength -WarningThresholdPercent $WarningThreshold `
        -ConflictTracker $tracker -SkipConflictCheck $skipConflictCheck
    foreach ($issue in $issues) {
        Add-IssueRecord -Issue $issue -IssueBag $allIssues -IssueCounts $issueCounts -IssueStats $issueStats `
            -MaxIssuesInMemory $MaxIssuesInMemory -IssuesInMemoryCount $issuesInMemoryCount -IssuesTruncated $issuesTruncatedRef
    }

    if (-not $isDir) {
        # Track top 10 files
        if ($size -gt $minTop10Size.Value -or $top10Files.Count -lt 10) {
            $top10Files.Add(@{ Name = $name; Path = $fullPath; Size = $size; SizeFormatted = Format-FileSize $size })
            if ($top10Files.Count -gt 10) {
                $sorted = $top10Files | Sort-Object { $_.Size } -Descending | Select-Object -First 10
                $top10Files.Clear()
                $sorted | ForEach-Object { $top10Files.Add($_) }
            }
            $minTop10Size.Value = if ($top10Files.Count -ge 10) { ($top10Files | Sort-Object { $_.Size } | Select-Object -First 1).Size } else { 0 }
        }

        $parentDir = Split-Path $fullPath -Parent
        if ($parentDir) {
            if (-not $folderFiles.ContainsKey($parentDir)) { $folderFiles.TryAdd($parentDir, [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()) | Out-Null }
            $folderFileCounts.AddOrUpdate($parentDir, 1, [Func[string,int,int]]{ param($k,$v) $v + 1 }) | Out-Null
            $folderFiles[$parentDir].Add(@{ Name = $name; Path = $fullPath; Size = $size; SizeFormatted = Format-FileSize $size })

            $parentPath = $parentDir
            while ($parentPath -and $parentPath.Length -ge $pathLen) {
                $folderSizes.AddOrUpdate($parentPath, $size, [Func[string,long,long]]{ param($k,$v) $v + $size }) | Out-Null
                $parentPath = [System.IO.Path]::GetDirectoryName($parentPath)
            }
        }
    }

    if ($progressTimer.ElapsedMilliseconds -ge 250) {
        $elapsed = (Get-Date) - $scanStart
        $elapsedStr = "{0:mm\:ss}" -f $elapsed
        $rate = Update-ETATracker -CurrentItems $itemCount.Value
        $rateStr = if ($rate -and $rate -gt 0) { Format-RateString -ItemsPerSecond $rate } else { "..." }
        $spinner = $spinnerChars[$spinnerIndex % 4]
        $spinnerIndex++

        Write-Host "`r    " -NoNewline
        Write-Host $spinner -NoNewline -ForegroundColor Cyan
        Write-Host " [" -NoNewline -ForegroundColor DarkGray
        Write-Host $elapsedStr -NoNewline -ForegroundColor White
        Write-Host "]  " -NoNewline -ForegroundColor DarkGray
        Write-Host ("{0:N0}" -f $itemCount.Value) -NoNewline -ForegroundColor Cyan
        Write-Host " items  " -NoNewline -ForegroundColor DarkGray
        Write-Host (Format-FileSize $totalSize.Value) -NoNewline -ForegroundColor Cyan
        Write-Host "  " -NoNewline -ForegroundColor DarkGray
        Write-Host ("{0:N0}" -f $issueCounts.Total) -NoNewline -ForegroundColor Yellow
        Write-Host " issues  " -NoNewline -ForegroundColor DarkGray
        Write-Host $rateStr -NoNewline -ForegroundColor Green
        Write-Host (" " * 10) -NoNewline
        $progressTimer.Restart()
    }

    if ($CheckpointInterval -gt 0 -and ($itemCount.Value - $lastCheckpointItems -ge $CheckpointInterval)) {
        Save-Checkpoint -SourcePath $Path -DestinationUrl $DestinationUrl -Counters @{
            ItemCount = $itemCount.Value
            FileCount = $fileCount.Value
            FolderCount = $folderCount.Value
            TotalSize = $totalSize.Value
            DirsProcessed = $folderCount.Value
        } -ScannedDirs $scannedDirsSet -FolderSizes $folderSizes -FolderFileCounts $folderFileCounts -RobocopyState @{
            LogPath = $robocopyLogPath
            Line = $robocopyLineNumber
            Complete = $robocopyComplete
        } -IssueCounts $issueCounts -IssueStats $issueStats
        $lastCheckpointItems = $itemCount.Value
    }
}

$robocopyComplete = $true
Save-Checkpoint -SourcePath $Path -DestinationUrl $DestinationUrl -Counters @{
    ItemCount = $itemCount.Value
    FileCount = $fileCount.Value
    FolderCount = $folderCount.Value
    TotalSize = $totalSize.Value
    DirsProcessed = $folderCount.Value
} -ScannedDirs $scannedDirsSet -FolderSizes $folderSizes -FolderFileCounts $folderFileCounts -RobocopyState @{
    LogPath = $robocopyLogPath
    Line = $robocopyLineNumber
    Complete = $robocopyComplete
} -IssueCounts $issueCounts -IssueStats $issueStats

$itemCount = $itemCount.Value
$fileCount = $fileCount.Value
$folderCount = $folderCount.Value
$totalSize = $totalSize.Value

Write-Host "`r    $($script:UI.Check) Scanned " -NoNewline
Write-Host ("{0:N0}" -f $itemCount) -NoNewline -ForegroundColor Cyan
Write-Host " items (" -NoNewline -ForegroundColor White
Write-Host (Format-FileSize $totalSize) -NoNewline -ForegroundColor Cyan
Write-Host ")                              " -ForegroundColor White

$scanEnd = Get-Date
$duration = $scanEnd - $scanStart

# Convert concurrent collections to standard formats for reporting
# Convert ConcurrentBag[hashtable] to array of PSCustomObjects
$issuesArray = @($allIssues.ToArray() | ForEach-Object { [PSCustomObject]$_ })

# Convert top10Files hashtables to PSCustomObjects
$top10FilesArray = @($top10Files | Sort-Object { $_.Size } -Descending | Select-Object -First 10 | ForEach-Object { [PSCustomObject]$_ })

# Get top 10 largest folders (excluding nested duplicates)
$allFoldersSorted = $folderSizes.GetEnumerator() | ForEach-Object {
    $folderPath = $_.Key
    # Convert ConcurrentBag to sorted array
    $directFiles = if ($folderFiles.ContainsKey($folderPath)) {
        @($folderFiles[$folderPath].ToArray() | Sort-Object { $_.Size } -Descending | Select-Object -First 20 | ForEach-Object { [PSCustomObject]$_ })
    } else { @() }
    [PSCustomObject]@{
        Name = Split-Path $_.Key -Leaf
        Path = $_.Key
        Size = $_.Value
        SizeFormatted = Format-FileSize $_.Value
        Files = $directFiles
        FileCount = if ($folderFileCounts.ContainsKey($folderPath)) { $folderFileCounts[$folderPath] } else { 0 }
    }
} | Sort-Object Size -Descending

# Filter out folders that are children of another folder already in the list
$top10Folders = @()
foreach ($folder in $allFoldersSorted) {
    $isNested = $false
    foreach ($existing in $top10Folders) {
        if ($folder.Path.StartsWith($existing.Path + '\') -or $folder.Path.StartsWith($existing.Path + '/')) {
            $isNested = $true
            break
        }
    }
    if (-not $isNested) {
        $top10Folders += $folder
        if ($top10Folders.Count -ge 10) { break }
    }
}

$results = [PSCustomObject]@{
    SourcePath = $Path
    DestinationUrl = $DestinationUrl
    ScanDate = $scanStart
    Duration = $duration
    TotalItems = $itemCount
    FileCount = $fileCount
    FolderCount = $folderCount
    TotalSize = $totalSize
    LargestFiles = $top10FilesArray
    LargestFolders = $top10Folders
    Issues = $issuesArray
    IssueCounts = [PSCustomObject]@{
        Critical = $issueCounts.Critical
        Warning = $issueCounts.Warning
        Info = $issueCounts.Info
        Total = $issueCounts.Total
    }
    IssueStats = [PSCustomObject]@{
        CAD = $issueStats.CAD
        Adobe = $issueStats.Adobe
        Database = $issueStats.Database
        Email = $issueStats.Email
        PathIssues = $issueStats.PathIssues
    }
    IssueLogPath = $script:IncrementalPath
    IssuesTruncated = $issuesInMemoryTruncated
}

# Summary
$critical = $results.IssueCounts.Critical
$warning = $results.IssueCounts.Warning
$info = $results.IssueCounts.Info
$score = Get-ReadinessScore -Critical $critical -Warning $warning

Write-Host ""
Write-Divider -Char "=" -Color Cyan
Write-Host ""
Write-Host "                        SCAN COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Divider -Char "=" -Color Cyan
Write-Host ""

# Stats row
Write-Host "    $($script:UI.Bullet) " -NoNewline -ForegroundColor Cyan
Write-Host "Items: " -NoNewline -ForegroundColor Gray
Write-Host ("{0:N0}" -f $itemCount) -NoNewline -ForegroundColor White
Write-Host "   $($script:UI.Bullet) " -NoNewline -ForegroundColor Cyan
Write-Host "Size: " -NoNewline -ForegroundColor Gray
Write-Host (Format-FileSize $totalSize) -NoNewline -ForegroundColor White
Write-Host "   $($script:UI.Bullet) " -NoNewline -ForegroundColor Cyan
Write-Host "Duration: " -NoNewline -ForegroundColor Gray
Write-Host ("{0:mm}:{0:ss}" -f $duration) -ForegroundColor White
Write-Host ""

# Readiness Score
Write-Host "    Readiness Score" -ForegroundColor White
Write-ProgressBar -Percent $score -Width 40
Write-Host ""
Write-Host ""

# Issue counts
Write-Host "    Issues Found" -ForegroundColor White
Write-Host ""
Write-TreeItem -Message "Critical" -Badge $critical -BadgeColor Red
Write-TreeItem -Message "Warning " -Badge $warning -BadgeColor Yellow
Write-TreeItem -Message "Info    " -Badge $info -BadgeColor Cyan -Last
Write-Host ""
if ($issuesInMemoryTruncated) {
    Write-Host "    Note: issue list truncated in memory; reports use the full incremental log." -ForegroundColor DarkGray
    Write-Host ""
}
Write-Divider
Write-Host ""

# Largest Files
if ($results.LargestFiles.Count -gt 0) {
    Write-Host "    $($script:UI.Arrow) " -NoNewline -ForegroundColor Magenta
    Write-Host "Top 10 Largest Files" -ForegroundColor White
    Write-Host ""
    $fileIndex = 0
    foreach ($file in $results.LargestFiles) {
        $fileIndex++
        $isLast = $fileIndex -eq $results.LargestFiles.Count
        $displayName = if ($file.Name.Length -gt 35) { $file.Name.Substring(0, 32) + "..." } else { $file.Name }
        Write-TreeItem -Message "$($file.SizeFormatted.PadLeft(10))  $displayName" -Last:$isLast -Color Gray
    }
    Write-Host ""
    Write-Divider
    Write-Host ""
}

# Largest Folders
if ($results.LargestFolders.Count -gt 0) {
    Write-Host "    $($script:UI.Arrow) " -NoNewline -ForegroundColor Magenta
    Write-Host "Top 10 Largest Folders" -ForegroundColor White
    Write-Host ""
    $folderIndex = 0
    foreach ($folder in $results.LargestFolders) {
        $folderIndex++
        $isLast = $folderIndex -eq $results.LargestFolders.Count
        # Show relative path from scan root
        $relativePath = $folder.Path.Replace($Path, "").TrimStart("\", "/")
        if ([string]::IsNullOrEmpty($relativePath)) { $relativePath = "(root)" }
        $displayPath = if ($relativePath.Length -gt 40) { "..." + $relativePath.Substring($relativePath.Length - 37) } else { $relativePath }
        Write-TreeItem -Message "$($folder.SizeFormatted.PadLeft(10))  $displayPath" -Last:$isLast -Color Gray
    }
    Write-Host ""
    Write-Divider
    Write-Host ""
}

# Migration Recommendations
$recommendations = Get-MigrationRecommendations -TotalFiles $itemCount -TotalSize $totalSize -Issues $results.Issues -IssueStats $results.IssueStats

Write-Host "    $($script:UI.Arrow) " -NoNewline -ForegroundColor Magenta
Write-Host "Migration Recommendation" -ForegroundColor White
Write-Host ""

$recIcon = switch ($recommendations.PrimaryIcon) {
    'critical' { $script:UI.Cross; 'Red' }
    'warning'  { '!'; 'Yellow' }
    'success'  { $script:UI.Check; 'Green' }
    default    { $script:UI.Bullet; 'Cyan' }
}
Write-Host "    $($recIcon[0]) " -NoNewline -ForegroundColor $recIcon[1]
Write-Host $recommendations.PrimaryRecommendation -ForegroundColor White
Write-Host ""
Write-Host "      " -NoNewline
Write-Host $recommendations.PrimaryReason -ForegroundColor DarkGray
Write-Host ""

if ($recommendations.Recommendations.Count -gt 0) {
    Write-Host "    Additional Considerations:" -ForegroundColor Gray
    $recIndex = 0
    foreach ($rec in $recommendations.Recommendations | Select-Object -First 4) {
        $recIndex++
        $isLast = $recIndex -eq [Math]::Min(4, $recommendations.Recommendations.Count)
        $recColor = switch ($rec.Icon) { 'critical' { 'Red' } 'warning' { 'Yellow' } default { 'Cyan' } }
        Write-TreeItem -Message $rec.Title -Last:$isLast -Color $recColor
    }
    Write-Host ""
}

Write-Host "    Access Method Summary:" -ForegroundColor Gray
Write-Host ""
foreach ($method in $recommendations.AccessMethods) {
    $verdictColor = switch ($method.Verdict) {
        'Recommended' { 'Green' }
        'Not Recommended' { 'Red' }
        'Consider' { 'Yellow' }
        default { 'DarkGray' }
    }
    Write-Host "      " -NoNewline
    Write-Host $method.Method.PadRight(32) -NoNewline -ForegroundColor White
    Write-Host $method.Verdict -ForegroundColor $verdictColor
}
Write-Host ""
Write-Divider
Write-Host ""

# Generate reports
if ('All' -in $OutputFormat) { $OutputFormat = @('HTML', 'CSV', 'JSON') }

Write-Host "    $($script:UI.Arrow) " -NoNewline -ForegroundColor Magenta
Write-Host "Reports" -ForegroundColor White
Write-Host ""

$reportIndex = 0
$reportCount = $OutputFormat.Count
foreach ($format in $OutputFormat) {
    $reportIndex++
    $isLast = $reportIndex -eq $reportCount
    $reportPath = New-Report -Results $results -OutputPath $OutputPath -Format $format
    Write-TreeItem -Message "$($format.PadRight(5)) $($script:UI.Arrow) " -Last:$isLast -Color Gray -Badge $reportPath -BadgeColor Cyan
}

Write-Host ""

# Clean up checkpoint on successful completion
Remove-CheckpointFiles
if (Test-Path $script:IncrementalPath) {
    Write-TreeItem -Message "Incremental issues log: $($script:IncrementalPath)" -Last:$true -Color Gray
}

Write-Divider -Char "=" -Color Cyan
Write-Host ""
Write-Host "    $($script:UI.Check) " -NoNewline -ForegroundColor Green
Write-Host "Done! Open the HTML report for interactive filtering." -ForegroundColor White
Write-Host ""
#endregion

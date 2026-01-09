# SharePoint Readiness Scanner

A high-performance CLI tool for MSPs to assess file system readiness before SharePoint Online migrations. Handles terabyte-scale datasets with parallel scanning, checkpoint/resume, and real-time progress.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)

## Quick Start (No Installation Required)

```powershell
# Run directly from the web - nothing to install!
irm https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/spready.ps1 | iex
```

Or with parameters:
```powershell
# Download and run with arguments
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/spready.ps1))) -Path "D:\Data" -DestinationUrl "https://contoso.sharepoint.com/sites/Project/Documents"
```

## Features

### Performance
- **Parallel Multi-Threaded Scanning** - Automatically uses multiple CPU cores
- **Work Queue with Load Balancing** - Dynamic work-stealing pattern for uneven directory trees
- **Memory-Aware Adaptive Parallelism** - Auto-detects available RAM, adjusts thread count
- **Optimized Validation** - Pre-compiled regex, HashSet O(1) lookups

### Reliability
- **Checkpoint/Resume** - Interrupted scan? Resume where you left off with `-Resume`
- **Incremental Results** - Issues streamed to file as found, view during long scans
- **ETA Tracking** - Real-time items/second rate display

### Validation Checks
- **URL-Encoded Path Length** - Accounts for spaces becoming `%20` in SharePoint URLs
- **9 Comprehensive Checks** - Path length, invalid characters, reserved names, blocked file types, problematic files, file size, name conflicts, hidden files, system files
- **Smart Recommendations** - Tailored migration approach based on your data profile

### Output
- **Beautiful CLI** - Interactive prompts, progress bars, colored output
- **Multiple Report Formats** - HTML (interactive dashboard), CSV (Excel), JSON (automation)
- **Expandable Folder View** - Click folders in HTML report to see their largest files

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Path` | Source directory to scan | *(interactive prompt)* |
| `-DestinationUrl` | SharePoint document library URL | *(interactive prompt)* |
| `-OutputPath` | Directory for reports | `.\SP-Readiness-Reports` |
| `-OutputFormat` | Report types: `HTML`, `CSV`, `JSON`, `All` | `HTML, CSV` |
| `-WarningThreshold` | Path length warning percentage | `80` |
| `-Resume` | Continue from previous checkpoint | `$false` |
| `-CheckpointInterval` | Directories between checkpoints | `500` |

## Usage Examples

### Interactive Mode (Recommended)
```powershell
# Just run it - guided prompts for everything
irm https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/spready.ps1 | iex
```

### Scripted Mode
```powershell
# Download once, run multiple times
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/spready.ps1" -OutFile spready.ps1

# Basic scan
.\spready.ps1 -Path "D:\FileServer" -DestinationUrl "https://contoso.sharepoint.com/sites/HR/Documents"

# Full options
.\spready.ps1 `
    -Path "\\server\share\data" `
    -DestinationUrl "https://contoso.sharepoint.com/sites/Project/Shared Documents" `
    -OutputPath "C:\Reports" `
    -OutputFormat All
```

### Resume Interrupted Scan
```powershell
# Scan got interrupted at 50%? Resume it:
.\spready.ps1 -Path "D:\BigData" -DestinationUrl "https://..." -Resume
```

### Monitor Long Scans
```powershell
# Watch incremental issues as they're found:
Get-Content .\SP-Readiness-Reports\scan_issues_*.jsonl -Wait | ConvertFrom-Json
```

## Validation Checks

| Check | Description | Severity |
|-------|-------------|----------|
| **Path Length** | URL-encoded path > 400 chars | Critical |
| **Path Warning** | Path approaching limit | Warning |
| **Invalid Characters** | Contains `" * : < > ? / \ \|` | Critical |
| **Reserved Names** | CON, PRN, AUX, NUL, COM0-9, LPT0-9, .lock | Critical |
| **Blocked Patterns** | Contains `_vti_` | Critical |
| **Blocked File Types** | .exe, .dll, .bat, etc. | Warning |
| **Problematic Files** | CAD, Adobe, databases, PST | Warning |
| **File Size** | Exceeds 250 GB limit | Critical |
| **Large Files** | > 10 GB (slow sync) | Warning |
| **Name Conflicts** | Case-insensitive duplicates | Warning |
| **Hidden Files** | Hidden attribute set | Info |
| **System Files** | System attribute set | Info |

## Problematic File Types

Files that upload but have known SharePoint/OneDrive issues:

| Category | Extensions | Issue |
|----------|------------|-------|
| **CAD/BIM** | .dwg, .rvt, .dgn, .sldprt | No file locking - users overwrite each other |
| **Adobe** | .psd, .ai, .indd, .prproj | Can't open from cloud, linked files break |
| **Databases** | .mdb, .accdb, .qbw, .sqlite | Corruption with cloud sync |
| **Email** | .pst, .ost | Locked while Outlook runs, huge re-uploads |

## Sample Output

```
    _____ _____    _____                _ _
   / ____|  __ \  |  __ \              | (_)
  | (___ | |__) | | |__) |___  __ _  __| |_ _ __   ___  ___ ___
   \___ \|  ___/  |  _  // _ \/ _` |/ _` | | '_ \ / _ \/ __/ __|
   ____) | |      | | \ \  __/ (_| | (_| | | | | |  __/\__ \__ \
  |_____/|_|      |_|  \_\___|\__,_|\__,_|_|_| |_|\___||___/___/

         SharePoint Migration Readiness Scanner
                    Portable Edition v1.0

  ------------------------------------------------------------
    High-Performance Mode: 15.2 GB available - 8 threads

    Scanned: 1,245,678 items  |  3.2 TB total  |  892 issues  |  45,231 dirs  |  12.5K/s

  ============================================================
                        SCAN COMPLETE
  ============================================================

    Readiness Score
    [====================================    ]  89%

    Issues Found
    ├── Critical  127
    ├── Warning    89
    └── Info      234
```

## Performance

Tested on real-world datasets:

| Dataset | Files | Size | Time | Rate |
|---------|-------|------|------|------|
| Small | 10K | 50 GB | ~10 sec | 1K/s |
| Medium | 500K | 500 GB | ~3 min | 2.5K/s |
| Large | 5M | 2 TB | ~25 min | 3.3K/s |
| Enterprise | 10M+ | 3.5 TB | ~45 min | 3.7K/s |

*Performance varies based on storage speed, CPU cores, and available memory.*

## Requirements

- PowerShell 5.1+ (Windows PowerShell) or PowerShell 7+ (cross-platform)
- Read access to the paths being scanned
- ~100MB RAM minimum, scales with thread count

## Module Version

For repeated use or integration, a PowerShell module version is also available:

```powershell
Import-Module .\SharePoint-Readiness
Test-SPReadiness -Path "D:\Data" -DestinationUrl "https://..."
```

## License

MIT License - see LICENSE file for details.

---

Built for MSPs doing SharePoint migrations at scale.

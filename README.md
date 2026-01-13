# SharePoint Readiness Scanner

Scans a local Windows file share and reports issues that block or slow SharePoint Online migrations. Generates HTML, CSV, and JSON reports. The destination URL is used only for path-length math; no SharePoint credentials or API calls are made.

## Requirements

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or PowerShell 7

## Quick Start (Windows PowerShell)

Interactive download and help:

```powershell
irm https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/install.ps1 | iex
```

Run with parameters (portal URL from SharePoint Online):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/install.ps1))) -Path "D:\Shares" -Destination "https://contoso.sharepoint.com/sites/IT/Shared Documents" -Output "C:\Reports"
```

Download once, run locally:

```powershell
irm https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/install.ps1 -OutFile install.ps1
.\install.ps1 -Path "D:\Shares" -Destination "https://contoso.sharepoint.com/sites/IT/Shared Documents"
```

## Portal-Only Checks

Provide `-Destination` with the target document library URL from the SharePoint Online portal (for example, `.../Shared Documents`). The scanner does not connect to SharePoint; it only uses the URL for length and naming checks.

## Usage

Interactive setup (TUI):

```powershell
spready.exe
```

Or force the TUI:

```powershell
spready.exe --tui
```

```powershell
spready.exe --path "D:\Shares" --destination "https://contoso.sharepoint.com/sites/IT/Shared Documents" --output "C:\Reports"
```

Quiet run (no banner or progress):

```powershell
spready.exe --path "D:\Shares" --no-banner --no-progress
```

## Command Line Options

```
Usage: spready [options]

Required:
  -path string
        Path to scan (required)

Optional:
  -destination string
        SharePoint destination URL (for path length calculation)
  -output string
        Output directory for reports (default ".")
  -json
        Generate JSON report (default true)
  -csv
        Generate CSV report (default true)
  -html
        Generate HTML report (default true)
  -max-items int
        Maximum items to scan, 0 = unlimited (default 0)
  -no-banner
        Suppress banner display
  -no-progress
        Suppress progress display
  -version
        Show version and exit
```

## Output Reports

- HTML report for interactive review
- CSV report for Excel or BI tools
- JSON report for automation

Reports are written to the output directory (`.` by default).

## Validation Checks

- Path length (including destination URL)
- File and folder name length
- Invalid characters and blocked patterns
- Reserved names
- Blocked file types
- Problematic file types
- File size limits
- Hidden and system files

## Exit Codes

- 0: No issues found
- 1: Warnings found
- 2: Critical issues found

## Build from Source (Windows)

```powershell
go build -o spready.exe ./cmd/spready
.\spready.exe --path "D:\Shares"
```

## License

MIT License. See `LICENSE` for details.

## Issues

Use `https://github.com/ajoshuasmith/SharePoint-Prescan/issues` for bug reports and feature requests.

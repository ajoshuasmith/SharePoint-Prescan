<#
.SYNOPSIS
    SharePoint-Readiness Quick Launcher

.DESCRIPTION
    Downloads and runs the SharePoint-Readiness scanner in one command.

.EXAMPLE
    irm ajoshuasmith.com/spready | iex

.EXAMPLE
    irm https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/run.ps1 | iex

.NOTES
    This script downloads the module to a temporary location and runs it.
    No permanent installation required.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Configuration
$repoOwner = "ajoshuasmith"
$repoName = "SharePoint-Prescan"
$branch = "main"
$moduleFolder = "SharePoint-Readiness"

# Colors and formatting
function Write-Header {
    $header = @"

    _____ ______   ____                 _ _
   / ____|  __ \ |  _ \               | (_)
  | (___ | |__) || |_) | ___  __ _  __| |_ _ __   ___  ___ ___
   \___ \|  ___/ |  _ < / _ \/ _`` |/ _`` | | '_ \ / _ \/ __/ __|
   ____) | |     | |_) |  __/ (_| | (_| | | | | |  __/\__ \__ \
  |_____/|_|     |____/ \___|\__,_|\__,_|_|_| |_|\___||___/___/

            SharePoint Migration Readiness Scanner
                        Quick Launcher

"@
    Write-Host $header -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message, [string]$Status = "...")
    Write-Host "  [" -NoNewline -ForegroundColor DarkGray
    Write-Host "*" -NoNewline -ForegroundColor Cyan
    Write-Host "] " -NoNewline -ForegroundColor DarkGray
    Write-Host $Message -NoNewline
    Write-Host " $Status" -ForegroundColor DarkGray
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [" -NoNewline -ForegroundColor DarkGray
    Write-Host "+" -NoNewline -ForegroundColor Green
    Write-Host "] " -NoNewline -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor Green
}

function Write-Error2 {
    param([string]$Message)
    Write-Host "  [" -NoNewline -ForegroundColor DarkGray
    Write-Host "!" -NoNewline -ForegroundColor Red
    Write-Host "] " -NoNewline -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor Red
}

# Main execution
try {
    Write-Header

    # Check PowerShell version
    Write-Step "Checking PowerShell version"
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5) {
        Write-Error2 "PowerShell 5.1 or higher required. Current: $psVersion"
        exit 1
    }
    Write-Success "PowerShell $psVersion detected"

    # Create temp directory
    Write-Step "Creating temporary directory"
    $tempBase = [System.IO.Path]::GetTempPath()
    $tempDir = Join-Path $tempBase "SPReadiness_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Write-Success "Created: $tempDir"

    # Download module
    Write-Step "Downloading SharePoint-Readiness module"

    $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip"
    $zipPath = Join-Path $tempDir "module.zip"

    try {
        # Try using Invoke-WebRequest
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    }
    catch {
        # Fallback to WebClient
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($zipUrl, $zipPath)
    }

    Write-Success "Downloaded module archive"

    # Extract module
    Write-Step "Extracting module"
    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
    Write-Success "Extracted successfully"

    # Find and import module
    Write-Step "Loading module"
    $extractedFolder = Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -like "*$repoName*" } | Select-Object -First 1
    $modulePath = Join-Path $extractedFolder.FullName $moduleFolder

    if (-not (Test-Path $modulePath)) {
        # Try alternative path structure
        $modulePath = Join-Path $extractedFolder.FullName "SharePoint-Readiness"
    }

    if (-not (Test-Path $modulePath)) {
        Write-Error2 "Module not found in downloaded archive"
        exit 1
    }

    Import-Module $modulePath -Force
    Write-Success "Module loaded successfully"

    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor DarkGray
    Write-Host ""

    # Run the scanner
    Test-SPReadiness

}
catch {
    Write-Host ""
    Write-Error2 "An error occurred: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "  For manual installation, visit:" -ForegroundColor Gray
    Write-Host "  https://github.com/$repoOwner/$repoName" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}
finally {
    # Cleanup temp files (optional - leave commented to debug)
    # if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}

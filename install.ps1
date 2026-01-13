# SharePoint-Prescan - Quick Install & Run Script
# Usage: irm https://raw.githubusercontent.com/ajoshuasmith/SharePoint-Prescan/main/install.ps1 | iex

param(
    [string]$Path,
    [string]$Destination,
    [string]$Output = ".",
    [switch]$SkipDownload,
    [switch]$Pause,
    [switch]$NoPrompt,
    [switch]$Tui
)

$ErrorActionPreference = "Stop"

# Detect platform and architecture
$os = if ($IsWindows -or $env:OS -match "Windows") { "windows" }
      elseif ($IsMacOS -or (uname) -eq "Darwin") { "darwin" }
      else { "linux" }

$arch = if ([Environment]::Is64BitOperatingSystem) {
    if ($os -eq "darwin" -and (uname -m) -eq "arm64") { "arm64" } else { "amd64" }
} else {
    throw "32-bit systems are not supported"
}

$binaryName = "spready-$os-$arch"
if ($os -eq "windows") { $binaryName += ".exe" }

$downloadUrl = "https://github.com/ajoshuasmith/SharePoint-Prescan/releases/latest/download/$binaryName"
$localPath = Join-Path $env:TEMP $binaryName

Write-Host ""
Write-Host "SharePoint-Prescan - Quick Install" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Platform: $os-$arch" -ForegroundColor Gray
Write-Host "Binary:   $binaryName" -ForegroundColor Gray
Write-Host ""

# Download if not already present or SkipDownload not set
if (-not $SkipDownload -and (-not (Test-Path $localPath) -or ((Get-Item $localPath).Length -eq 0))) {
    Write-Host "Downloading binary..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $localPath -UseBasicParsing
        Write-Host "Downloaded successfully" -ForegroundColor Green
    } catch {
        Write-Host "Failed to download from: $downloadUrl" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "To build from source instead:" -ForegroundColor Yellow
        Write-Host "  git clone https://github.com/ajoshuasmith/SharePoint-Prescan.git" -ForegroundColor Gray
        Write-Host "  cd SharePoint-Prescan" -ForegroundColor Gray
        Write-Host "  go build -o spready ./cmd/spready" -ForegroundColor Gray
        exit 1
    }
}

# Make executable on Unix
if ($os -ne "windows") {
    chmod +x $localPath 2>$null
}

Write-Host ""

$interactive = $false
$useTui = $false

if ($Tui) {
    $useTui = $true
    $interactive = $true
} elseif (-not $Path -and -not $NoPrompt) {
    $useTui = $true
    $interactive = $true
}

# If no path provided, show usage
if (-not $Path -and -not $useTui) {
    Write-Host "Usage Examples:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  # Interactive download and run:" -ForegroundColor Gray
    Write-Host "  irm https://raw.githubusercontent.com/.../install.ps1 | iex" -ForegroundColor White
    Write-Host ""
    Write-Host "  # With parameters:" -ForegroundColor Gray
    Write-Host '  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/.../install.ps1))) -Path "C:\Data"' -ForegroundColor White
    Write-Host ""
    Write-Host "  # Download once, run multiple times:" -ForegroundColor Gray
    Write-Host "  irm https://raw.githubusercontent.com/.../install.ps1 -OutFile install.ps1" -ForegroundColor White
    Write-Host '  .\install.ps1 -Path "C:\Data" -Destination "https://contoso.sharepoint.com/..."' -ForegroundColor White
    Write-Host ""
    Write-Host "Binary downloaded to: $localPath" -ForegroundColor Green
    Write-Host "You can run it directly:" -ForegroundColor Gray
    Write-Host "  $localPath --path `"C:\Data`"" -ForegroundColor White
    Write-Host ""
    exit 0
}

# Build arguments
$args = @()
if ($useTui) { $args += @("--tui") }
if ($Path) { $args += @("--path", $Path) }
if ($Destination) { $args += @("--destination", $Destination) }
if ($Output -ne ".") { $args += @("--output", $Output) }

# Run the scanner
Write-Host "Running scan..." -ForegroundColor Green
Write-Host ""

& $localPath @args

$exitCode = $LASTEXITCODE
Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "Scan completed successfully!" -ForegroundColor Green
} elseif ($exitCode -eq 1) {
    Write-Host "Scan completed with warnings" -ForegroundColor Yellow
} elseif ($exitCode -eq 2) {
    Write-Host "Scan completed with critical issues" -ForegroundColor Red
}

Write-Host ""
Write-Host "Binary location: $localPath" -ForegroundColor Gray
Write-Host "To run again: $localPath --path `"<path>`"" -ForegroundColor Gray
Write-Host ""

if ($Pause -or $interactive) {
    Read-Host "Press Enter to close"
}

exit $exitCode

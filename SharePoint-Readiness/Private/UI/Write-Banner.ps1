function Write-Banner {
    <#
    .SYNOPSIS
        Displays the SharePoint-Readiness ASCII banner.

    .DESCRIPTION
        Shows a stylized ASCII art banner with the tool name and version.

    .PARAMETER Version
        The version string to display.

    .PARAMETER NoColor
        If true, displays without colors.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Version = "1.0.0",

        [Parameter()]
        [switch]$NoColor
    )

    $banner = @"

    _____ ______   ____                 _ _
   / ____|  __ \ |  _ \               | (_)
  | (___ | |__) || |_) | ___  __ _  __| |_ _ __   ___  ___ ___
   \___ \|  ___/ |  _ < / _ \/ _`` |/ _`` | | '_ \ / _ \/ __/ __|
   ____) | |     | |_) |  __/ (_| | (_| | | | | |  __/\__ \__ \
  |_____/|_|     |____/ \___|\__,_|\__,_|_|_| |_|\___||___/___/

"@

    $subtitle = "           SharePoint Migration Readiness Scanner"
    $versionLine = "                         v$Version"
    $separator = "  " + ("=" * 60)

    if ($NoColor) {
        Write-Host $banner
        Write-Host $subtitle
        Write-Host $versionLine
        Write-Host ""
        Write-Host $separator
        Write-Host ""
    }
    else {
        Write-Host $banner -ForegroundColor Cyan
        Write-Host $subtitle -ForegroundColor White
        Write-Host $versionLine -ForegroundColor DarkGray
        Write-Host ""
        Write-Host $separator -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Write-Section {
    <#
    .SYNOPSIS
        Writes a section header.

    .DESCRIPTION
        Displays a formatted section header with optional icon.

    .PARAMETER Title
        The section title.

    .PARAMETER Icon
        Optional icon character to display.

    .PARAMETER Color
        The color for the title.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string]$Icon = "",

        [Parameter()]
        [string]$Color = "Cyan"
    )

    Write-Host ""
    if ($Icon) {
        Write-Host "  $Icon " -NoNewline -ForegroundColor $Color
    }
    else {
        Write-Host "  " -NoNewline
    }
    Write-Host $Title -ForegroundColor $Color
    Write-Host "  $("-" * ($Title.Length + 2))" -ForegroundColor DarkGray
}

function Write-StatusLine {
    <#
    .SYNOPSIS
        Writes a status line with label and value.

    .DESCRIPTION
        Displays a formatted line with a label and value, optionally colored.

    .PARAMETER Label
        The label text.

    .PARAMETER Value
        The value to display.

    .PARAMETER ValueColor
        The color for the value.

    .PARAMETER Indent
        Number of spaces to indent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter()]
        [string]$ValueColor = "White",

        [Parameter()]
        [int]$Indent = 4,

        [Parameter()]
        [int]$LabelWidth = 25
    )

    $padding = " " * $Indent
    $labelPadded = $Label.PadRight($LabelWidth)

    Write-Host "$padding$labelPadded" -NoNewline -ForegroundColor Gray
    Write-Host $Value -ForegroundColor $ValueColor
}

function Write-SPProgress {
    <#
    .SYNOPSIS
        Displays a custom progress bar for scanning operations.

    .DESCRIPTION
        Shows a visual progress bar with percentage, counts, and optional status message.

    .PARAMETER Activity
        The activity name (e.g., "Scanning files").

    .PARAMETER Status
        Current status message.

    .PARAMETER PercentComplete
        Percentage complete (0-100).

    .PARAMETER CurrentItem
        Current item number.

    .PARAMETER TotalItems
        Total number of items (if known).

    .PARAMETER NoNewLine
        If true, stays on the same line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Activity,

        [Parameter()]
        [string]$Status = "",

        [Parameter()]
        [int]$PercentComplete = -1,

        [Parameter()]
        [int]$CurrentItem = 0,

        [Parameter()]
        [int]$TotalItems = 0,

        [Parameter()]
        [switch]$NoNewLine,

        [Parameter()]
        [switch]$Complete
    )

    # Progress bar settings
    $barWidth = 40
    $filledChar = [char]0x2588  # Full block
    $emptyChar = [char]0x2591  # Light shade

    # Calculate progress
    if ($PercentComplete -ge 0) {
        $percent = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
    }
    elseif ($TotalItems -gt 0) {
        $percent = [Math]::Round(($CurrentItem / $TotalItems) * 100)
    }
    else {
        $percent = -1  # Indeterminate
    }

    # Build progress bar
    if ($percent -ge 0) {
        $filledWidth = [Math]::Round($barWidth * ($percent / 100))
        $emptyWidth = $barWidth - $filledWidth

        $bar = ($filledChar.ToString() * $filledWidth) + ($emptyChar.ToString() * $emptyWidth)

        # Color based on completion
        $barColor = if ($percent -eq 100) { 'Green' }
                    elseif ($percent -ge 75) { 'Cyan' }
                    elseif ($percent -ge 50) { 'Yellow' }
                    else { 'White' }
    }
    else {
        # Indeterminate progress (spinning indicator)
        $spinChars = @('-', '\', '|', '/')
        $spinIndex = $CurrentItem % 4
        $bar = " " * 18 + $spinChars[$spinIndex] + " Processing..." + " " * 18
        $barColor = 'Yellow'
        $percent = 0
    }

    # Build count string
    $countStr = if ($TotalItems -gt 0) {
        "{0:N0} / {1:N0}" -f $CurrentItem, $TotalItems
    }
    else {
        "{0:N0}" -f $CurrentItem
    }

    # Build the line
    $line = "  $Activity "

    # Clear line and return to start
    Write-Host "`r$(' ' * 100)`r" -NoNewline

    # Write components
    Write-Host "  " -NoNewline
    Write-Host $Activity -NoNewline -ForegroundColor White
    Write-Host " [" -NoNewline -ForegroundColor DarkGray

    if ($percent -ge 0) {
        Write-Host $bar -NoNewline -ForegroundColor $barColor
    }
    else {
        Write-Host $bar -NoNewline -ForegroundColor $barColor
    }

    Write-Host "] " -NoNewline -ForegroundColor DarkGray

    if ($percent -ge 0) {
        $percentStr = "{0,3}%" -f $percent
        Write-Host $percentStr -NoNewline -ForegroundColor $barColor
    }

    Write-Host " | " -NoNewline -ForegroundColor DarkGray
    Write-Host $countStr -NoNewline -ForegroundColor Gray

    if ($Status) {
        Write-Host " | " -NoNewline -ForegroundColor DarkGray
        Write-Host $Status -NoNewline -ForegroundColor DarkGray
    }

    if (-not $NoNewLine -or $Complete) {
        Write-Host ""
    }
}

function Write-ScanProgress {
    <#
    .SYNOPSIS
        Updates scan progress with tree-style formatting.

    .DESCRIPTION
        Shows hierarchical progress for multi-step scanning operations.

    .PARAMETER Step
        Current step name.

    .PARAMETER StepNumber
        Current step number.

    .PARAMETER TotalSteps
        Total number of steps.

    .PARAMETER ItemCount
        Number of items processed in current step.

    .PARAMETER IsComplete
        If true, marks the step as complete.

    .PARAMETER IsLast
        If true, uses end-of-tree connector.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Step,

        [Parameter()]
        [int]$StepNumber = 1,

        [Parameter()]
        [int]$TotalSteps = 1,

        [Parameter()]
        [int]$ItemCount = 0,

        [Parameter()]
        [switch]$IsComplete,

        [Parameter()]
        [switch]$IsLast
    )

    $connector = if ($IsLast) { "`u{2514}" } else { "`u{251C}" }  # └ or ├
    $status = if ($IsComplete) { "[Done]" } else { "[...]" }
    $statusColor = if ($IsComplete) { "Green" } else { "Yellow" }

    Write-Host "  $connector" -NoNewline -ForegroundColor DarkGray
    Write-Host "── " -NoNewline -ForegroundColor DarkGray
    Write-Host $Step -NoNewline -ForegroundColor White

    if ($ItemCount -gt 0) {
        Write-Host " (" -NoNewline -ForegroundColor DarkGray
        Write-Host ("{0:N0}" -f $ItemCount) -NoNewline -ForegroundColor Cyan
        Write-Host " items)" -NoNewline -ForegroundColor DarkGray
    }

    Write-Host " $status" -ForegroundColor $statusColor
}

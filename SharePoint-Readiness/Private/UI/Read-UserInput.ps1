function Read-UserInput {
    <#
    .SYNOPSIS
        Prompts user for input with validation.

    .DESCRIPTION
        Displays a prompt and reads user input, optionally validating against
        a set of allowed values or a validation script.

    .PARAMETER Prompt
        The prompt text to display.

    .PARAMETER Default
        Default value if user presses Enter without input.

    .PARAMETER ValidValues
        Array of valid values (for selection prompts).

    .PARAMETER ValidationScript
        Script block to validate input. Should return $true for valid input.

    .PARAMETER Required
        If true, empty input is not allowed.

    .PARAMETER IsPath
        If true, validates as a file system path.

    .PARAMETER IsUrl
        If true, validates as a URL.

    .OUTPUTS
        The validated user input string.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [string]$Default = "",

        [Parameter()]
        [string[]]$ValidValues,

        [Parameter()]
        [scriptblock]$ValidationScript,

        [Parameter()]
        [switch]$Required,

        [Parameter()]
        [switch]$IsPath,

        [Parameter()]
        [switch]$IsUrl,

        [Parameter()]
        [string]$ErrorMessage = "Invalid input. Please try again."
    )

    while ($true) {
        # Build prompt string
        $promptText = "  ? $Prompt"
        if ($Default) {
            $promptText += " [$Default]"
        }
        $promptText += ": "

        # Display prompt
        Write-Host $promptText -NoNewline -ForegroundColor Cyan
        $input = Read-Host

        # Use default if empty
        if ([string]::IsNullOrWhiteSpace($input) -and $Default) {
            $input = $Default
        }

        # Check if required
        if ($Required -and [string]::IsNullOrWhiteSpace($input)) {
            Write-Host "    This field is required." -ForegroundColor Red
            continue
        }

        # Allow empty input if not required
        if (-not $Required -and [string]::IsNullOrWhiteSpace($input)) {
            return $input
        }

        # Validate path
        if ($IsPath) {
            $input = $input.Trim('"', "'")
            if (-not (Test-Path -Path $input -PathType Container)) {
                Write-Host "    Path does not exist or is not accessible: $input" -ForegroundColor Red
                continue
            }
        }

        # Validate URL
        if ($IsUrl) {
            if (-not ($input -match '^https?://')) {
                Write-Host "    Please enter a valid URL starting with http:// or https://" -ForegroundColor Red
                continue
            }
        }

        # Check valid values
        if ($ValidValues -and $input -notin $ValidValues) {
            Write-Host "    Please enter one of: $($ValidValues -join ', ')" -ForegroundColor Red
            continue
        }

        # Run validation script
        if ($ValidationScript) {
            $isValid = & $ValidationScript $input
            if (-not $isValid) {
                Write-Host "    $ErrorMessage" -ForegroundColor Red
                continue
            }
        }

        return $input
    }
}

function Read-MenuSelection {
    <#
    .SYNOPSIS
        Displays a menu and reads user selection.

    .DESCRIPTION
        Shows numbered menu options and prompts user to select one or more.

    .PARAMETER Title
        The menu title.

    .PARAMETER Options
        Array of option strings or hashtables with Name/Value pairs.

    .PARAMETER MultiSelect
        If true, allows selecting multiple options.

    .PARAMETER DefaultSelections
        Array of indices that are selected by default (for multi-select).

    .OUTPUTS
        Selected option(s).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [array]$Options,

        [Parameter()]
        [switch]$MultiSelect,

        [Parameter()]
        [int[]]$DefaultSelections = @()
    )

    Write-Host ""
    Write-Host "  ? $Title" -ForegroundColor Cyan

    # Track selections for multi-select
    $selected = @{}
    foreach ($i in $DefaultSelections) {
        $selected[$i] = $true
    }

    for ($i = 0; $i -lt $Options.Count; $i++) {
        $option = $Options[$i]
        $name = if ($option -is [hashtable]) { $option.Name } else { $option }

        if ($MultiSelect) {
            $checkbox = if ($selected[$i]) { "[x]" } else { "[ ]" }
            Write-Host "    $checkbox " -NoNewline -ForegroundColor $(if ($selected[$i]) { 'Green' } else { 'Gray' })
        }
        else {
            Write-Host "    [$($i + 1)] " -NoNewline -ForegroundColor Yellow
        }

        Write-Host $name -ForegroundColor White
    }

    if ($MultiSelect) {
        Write-Host ""
        Write-Host "  Enter numbers to toggle (comma-separated), or 'done': " -NoNewline -ForegroundColor DarkGray
        $input = Read-Host

        if ($input -ieq 'done' -or [string]::IsNullOrEmpty($input)) {
            return $Options | Where-Object { $selected[$Options.IndexOf($_)] }
        }

        # Parse selections
        $numbers = $input -split ',' | ForEach-Object { $_.Trim() }
        foreach ($num in $numbers) {
            if ($num -match '^\d+$') {
                $index = [int]$num - 1
                if ($index -ge 0 -and $index -lt $Options.Count) {
                    $selected[$index] = -not $selected[$index]
                }
            }
        }

        # Recurse to show updated selections
        return Read-MenuSelection -Title $Title -Options $Options -MultiSelect -DefaultSelections ($selected.Keys | Where-Object { $selected[$_] })
    }
    else {
        Write-Host ""
        Write-Host "  Enter selection [1-$($Options.Count)]: " -NoNewline -ForegroundColor DarkGray
        $input = Read-Host

        if ($input -match '^\d+$') {
            $index = [int]$input - 1
            if ($index -ge 0 -and $index -lt $Options.Count) {
                return $Options[$index]
            }
        }

        Write-Host "    Invalid selection. Please enter a number between 1 and $($Options.Count)." -ForegroundColor Red
        return Read-MenuSelection -Title $Title -Options $Options
    }
}

function Read-YesNo {
    <#
    .SYNOPSIS
        Prompts for a yes/no confirmation.

    .PARAMETER Prompt
        The prompt text.

    .PARAMETER Default
        Default value ('Y' or 'N').

    .OUTPUTS
        Boolean - $true for yes, $false for no.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [ValidateSet('Y', 'N')]
        [string]$Default = 'Y'
    )

    $options = if ($Default -eq 'Y') { '[Y/n]' } else { '[y/N]' }

    Write-Host "  ? $Prompt $options " -NoNewline -ForegroundColor Cyan
    $input = Read-Host

    if ([string]::IsNullOrWhiteSpace($input)) {
        return $Default -eq 'Y'
    }

    return $input -imatch '^y(es)?$'
}

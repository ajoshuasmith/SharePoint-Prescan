function Get-ConsoleColors {
    <#
    .SYNOPSIS
        Returns the color scheme for console output.

    .DESCRIPTION
        Provides consistent color definitions for the CLI interface.

    .OUTPUTS
        Hashtable with color definitions.
    #>
    [CmdletBinding()]
    param()

    @{
        # Severity colors
        Critical = 'Red'
        Warning = 'Yellow'
        Info = 'Cyan'
        Success = 'Green'

        # UI element colors
        Banner = 'Cyan'
        Title = 'White'
        Subtitle = 'Gray'
        Prompt = 'Cyan'
        Input = 'White'
        Value = 'White'
        Label = 'Gray'
        Muted = 'DarkGray'
        Separator = 'DarkGray'

        # Progress colors
        ProgressLow = 'Red'
        ProgressMedium = 'Yellow'
        ProgressHigh = 'Green'
        ProgressBar = 'Cyan'
        ProgressBackground = 'DarkGray'

        # Status colors
        StatusPending = 'Yellow'
        StatusRunning = 'Cyan'
        StatusComplete = 'Green'
        StatusFailed = 'Red'

        # File type colors
        FileNormal = 'White'
        FileBlocked = 'Red'
        FileProblematic = 'Yellow'
        FileHidden = 'DarkGray'
        FolderNormal = 'Blue'
        FolderEmpty = 'DarkGray'
    }
}

function Get-SeverityColor {
    <#
    .SYNOPSIS
        Gets the console color for a severity level.

    .PARAMETER Severity
        The severity level (Critical, Warning, Info).

    .OUTPUTS
        ConsoleColor value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Warning', 'Info')]
        [string]$Severity
    )

    switch ($Severity) {
        'Critical' { 'Red' }
        'Warning' { 'Yellow' }
        'Info' { 'Cyan' }
        default { 'White' }
    }
}

function Get-SeverityIcon {
    <#
    .SYNOPSIS
        Gets the icon character for a severity level.

    .PARAMETER Severity
        The severity level.

    .PARAMETER Style
        Icon style: 'Circle', 'Square', 'Emoji'.

    .OUTPUTS
        Icon character.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'Warning', 'Info', 'Success')]
        [string]$Severity,

        [Parameter()]
        [ValidateSet('Circle', 'Square', 'Emoji', 'Text')]
        [string]$Style = 'Circle'
    )

    switch ($Style) {
        'Circle' {
            switch ($Severity) {
                'Critical' { [char]0x25CF }  # ●
                'Warning' { [char]0x25CF }
                'Info' { [char]0x25CF }
                'Success' { [char]0x25CF }
            }
        }
        'Square' {
            switch ($Severity) {
                'Critical' { [char]0x25A0 }  # ■
                'Warning' { [char]0x25A0 }
                'Info' { [char]0x25A0 }
                'Success' { [char]0x25A0 }
            }
        }
        'Emoji' {
            switch ($Severity) {
                'Critical' { '!!' }
                'Warning' { '!' }
                'Info' { 'i' }
                'Success' { '*' }
            }
        }
        'Text' {
            switch ($Severity) {
                'Critical' { 'CRITICAL' }
                'Warning' { 'WARNING' }
                'Info' { 'INFO' }
                'Success' { 'SUCCESS' }
            }
        }
    }
}

function Test-ConsoleSupportsUnicode {
    <#
    .SYNOPSIS
        Tests if the console supports Unicode characters.

    .DESCRIPTION
        Checks if the current console can display Unicode characters properly.

    .OUTPUTS
        Boolean indicating Unicode support.
    #>
    [CmdletBinding()]
    param()

    try {
        # Check if running in Windows Terminal or modern console
        if ($env:WT_SESSION) {
            return $true
        }

        # Check console output encoding
        if ([Console]::OutputEncoding.WebName -match 'utf-8|utf-16') {
            return $true
        }

        # Check for Windows PowerShell ISE (supports Unicode)
        if ($Host.Name -eq 'Windows PowerShell ISE Host') {
            return $true
        }

        # Check for VS Code integrated terminal
        if ($env:TERM_PROGRAM -eq 'vscode') {
            return $true
        }

        return $false
    }
    catch {
        return $false
    }
}

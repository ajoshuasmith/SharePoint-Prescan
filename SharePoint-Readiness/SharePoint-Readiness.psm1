#Requires -Version 5.1
<#
.SYNOPSIS
    SharePoint-Readiness PowerShell Module

.DESCRIPTION
    A comprehensive tool for assessing file system readiness before
    migrating to SharePoint Online. Identifies path length issues,
    invalid characters, blocked file types, and other compatibility
    concerns.

.NOTES
    Module: SharePoint-Readiness
    Version: 1.0.0
    Author: SharePoint-Readiness Team
#>

# Get module root path
$ModuleRoot = $PSScriptRoot

# Import private functions (helpers, validators, etc.)
$PrivateFunctions = @(
    # Helpers
    'Private\Helpers\Format-FileSize.ps1'
    'Private\Helpers\Get-UrlEncodedLength.ps1'
    'Private\Helpers\ConvertTo-SPPath.ps1'

    # Validators
    'Private\Validators\Test-PathLength.ps1'
    'Private\Validators\Test-InvalidCharacters.ps1'
    'Private\Validators\Test-ReservedNames.ps1'
    'Private\Validators\Test-BlockedFileTypes.ps1'
    'Private\Validators\Test-ProblematicFiles.ps1'
    'Private\Validators\Test-FileSize.ps1'
    'Private\Validators\Test-NameConflicts.ps1'
    'Private\Validators\Test-SpecialFiles.ps1'

    # Scanners
    'Private\Scanners\Get-FileSystemItems.ps1'
    'Private\Scanners\Measure-DestinationPath.ps1'

    # UI
    'Private\UI\Write-Banner.ps1'
    'Private\UI\Write-SPProgress.ps1'
    'Private\UI\Write-Summary.ps1'
    'Private\UI\Read-UserInput.ps1'
    'Private\UI\Get-ConsoleColors.ps1'

    # Reporters
    'Private\Reporters\New-HtmlReport.ps1'
    'Private\Reporters\New-CsvReport.ps1'
    'Private\Reporters\New-JsonReport.ps1'
)

foreach ($function in $PrivateFunctions) {
    $functionPath = Join-Path $ModuleRoot $function
    if (Test-Path $functionPath) {
        try {
            . $functionPath
            Write-Verbose "Loaded: $function"
        }
        catch {
            Write-Error "Failed to load $function : $_"
        }
    }
    else {
        Write-Warning "Function file not found: $functionPath"
    }
}

# Import public functions
$PublicFunctions = @(
    'Public\Test-SPReadiness.ps1'
)

foreach ($function in $PublicFunctions) {
    $functionPath = Join-Path $ModuleRoot $function
    if (Test-Path $functionPath) {
        try {
            . $functionPath
            Write-Verbose "Loaded: $function"
        }
        catch {
            Write-Error "Failed to load $function : $_"
        }
    }
    else {
        Write-Warning "Function file not found: $functionPath"
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Test-SPReadiness'
    'Measure-DestinationPath'
    'Format-FileSize'
)

# Export aliases
Export-ModuleMember -Alias @(
    'spready'
)

# Module initialization message
Write-Verbose "SharePoint-Readiness module loaded. Use 'Test-SPReadiness' or 'spready' to start scanning."

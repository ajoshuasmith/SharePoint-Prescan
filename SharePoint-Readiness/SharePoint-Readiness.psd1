@{
    # Module manifest for SharePoint-Readiness

    # Script module or binary module file associated with this manifest
    RootModule = 'SharePoint-Readiness.psm1'

    # Version number of this module
    ModuleVersion = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author = 'SharePoint-Readiness Team'

    # Company or vendor of this module
    CompanyName = 'MSP Tools'

    # Copyright statement for this module
    Copyright = '(c) 2024. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Assesses file system readiness for SharePoint Online migration. Identifies path length issues, invalid characters, blocked file types, name conflicts, and other compatibility concerns. Generates interactive HTML, CSV, and JSON reports.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Functions to export from this module
    FunctionsToExport = @(
        'Test-SPReadiness'
        'Measure-DestinationPath'
        'Format-FileSize'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @(
        'spready'
    )

    # List of all files packaged with this module
    FileList = @(
        'SharePoint-Readiness.psd1'
        'SharePoint-Readiness.psm1'
        'Config\SPO-Limits.psd1'
        'Config\BlockedFileTypes.psd1'
        'Config\ProblematicFileTypes.psd1'
        'Config\DefaultSettings.psd1'
    )

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for discoverability
            Tags = @(
                'SharePoint'
                'SharePointOnline'
                'Migration'
                'Readiness'
                'Assessment'
                'FileServer'
                'MSP'
                'M365'
                'Microsoft365'
            )

            # A URL to the license for this module
            LicenseUri = ''

            # A URL to the main website for this project
            ProjectUri = ''

            # A URL to an icon representing this module
            IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
## Version 1.0.0

Initial release with the following features:

### Validation Checks
- Path length analysis (400 character limit with destination URL calculation)
- Invalid character detection (" * : < > ? / \ |)
- Reserved name detection (CON, PRN, AUX, NUL, etc.)
- Blocked file type identification
- Problematic file type warnings (CAD, Adobe, databases, PST)
- File size validation (250 GB limit)
- Name conflict detection (case-insensitive)
- Hidden and system file identification

### User Interface
- Beautiful interactive CLI with ASCII banner
- Real-time progress bars
- Colored output with severity indicators
- Interactive prompts for guided scanning

### Reporting
- Interactive HTML report with filtering and sorting
- CSV export for Excel analysis
- JSON export for automation
- Readiness score calculation

### Key Features
- SharePoint destination URL aware path calculation
- Configurable warning thresholds
- Comprehensive remediation suggestions
- Support for both interactive and scripted use
'@

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance
            RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module
    # DefaultCommandPrefix = ''
}

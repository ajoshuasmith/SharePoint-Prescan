@{
    # SharePoint Online Path and File Limits
    # Reference: https://support.microsoft.com/en-us/office/restrictions-and-limitations-in-onedrive-and-sharepoint

    # Maximum total path length (decoded URL, excludes tenant domain)
    MaxPathLength = 400

    # Maximum individual file or folder name length
    MaxFileNameLength = 255

    # Maximum file size in bytes (250 GB)
    MaxFileSizeBytes = 268435456000

    # Characters that cannot be used in file or folder names
    InvalidCharacters = @(
        '"'   # Double quote
        '*'   # Asterisk
        ':'   # Colon
        '<'   # Less than
        '>'   # Greater than
        '?'   # Question mark
        '/'   # Forward slash
        '\'   # Backslash
        '|'   # Pipe
    )

    # Reserved names that cannot be used for files or folders
    ReservedNames = @(
        '.lock'
        'CON'
        'PRN'
        'AUX'
        'NUL'
        'COM0', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9'
        'LPT0', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
        'desktop.ini'
        '_vti_'
    )

    # Patterns that cannot appear anywhere in the path
    BlockedPatterns = @(
        '_vti_'
    )

    # Blocked prefixes for files and folders
    BlockedPrefixes = @{
        File = @('~$')
        Folder = @('~')
    }

    # Names that cannot be used at root level of a library
    RootLevelBlockedNames = @(
        'forms'
    )
}

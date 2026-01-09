function Measure-DestinationPath {
    <#
    .SYNOPSIS
        Calculates the character length of a SharePoint destination URL.

    .DESCRIPTION
        Parses a SharePoint Online URL and calculates the path length that will
        be prepended to migrated files. This helps determine available character
        budget for file paths.

    .PARAMETER DestinationUrl
        The full SharePoint destination URL, e.g.:
        https://contoso.sharepoint.com/sites/ProjectX/Shared Documents

    .OUTPUTS
        PSCustomObject with path analysis details.

    .EXAMPLE
        Measure-DestinationPath -DestinationUrl "https://contoso.sharepoint.com/sites/HR/Shared Documents/2024"

        Returns:
        TenantUrl           : https://contoso.sharepoint.com
        SitePath            : /sites/HR
        LibraryPath         : /Shared Documents/2024
        PathLength          : 29
        AvailableChars      : 371
        UrlEncodedLength    : 33
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DestinationUrl
    )

    # Clean up URL
    $url = $DestinationUrl.Trim().TrimEnd('/')

    # Validate URL format
    if (-not ($url -match '^https?://')) {
        throw "Invalid URL format. URL must start with http:// or https://"
    }

    try {
        $uri = [System.Uri]::new($url)
    }
    catch {
        throw "Invalid URL format: $($_.Exception.Message)"
    }

    # Parse SharePoint URL components
    # Format: https://tenant.sharepoint.com/sites/sitename/library/folder/subfolder
    # Or: https://tenant.sharepoint.com/library/folder (root site)

    $tenantUrl = "$($uri.Scheme)://$($uri.Host)"
    $fullPath = $uri.AbsolutePath.TrimStart('/')

    # Determine site path and library path
    $sitePath = ''
    $libraryPath = ''

    if ($fullPath -match '^(sites|teams)/([^/]+)(.*)$') {
        # Site collection URL
        $sitePath = "/$($Matches[1])/$($Matches[2])"
        $libraryPath = $Matches[3]
    }
    else {
        # Root site or direct library URL
        $libraryPath = "/$fullPath"
    }

    # The path that counts toward the 400 char limit is:
    # sitePath + libraryPath (excluding tenant domain)
    $countedPath = $sitePath + $libraryPath
    $pathLength = $countedPath.Length

    # Calculate URL-encoded length (spaces become %20, etc.)
    $encodedPath = [System.Uri]::EscapeDataString($countedPath) -replace '%2F', '/'
    $encodedLength = $encodedPath.Length

    # Use the larger value (SharePoint counts encoded characters)
    $effectiveLength = [Math]::Max($pathLength, $encodedLength)

    # Calculate available characters
    $maxPathLength = 400
    $availableChars = $maxPathLength - $effectiveLength

    # Create result object
    $result = [PSCustomObject]@{
        OriginalUrl = $DestinationUrl
        TenantUrl = $tenantUrl
        TenantDomain = $uri.Host
        SitePath = $sitePath
        LibraryPath = $libraryPath
        FullSharePointPath = $countedPath
        PathLength = $pathLength
        UrlEncodedPath = $encodedPath
        UrlEncodedLength = $encodedLength
        EffectiveLength = $effectiveLength
        MaxPathLength = $maxPathLength
        AvailableChars = $availableChars
        PercentUsed = [Math]::Round(($effectiveLength / $maxPathLength) * 100, 1)
    }

    # Add warnings if applicable
    if ($availableChars -lt 100) {
        $result | Add-Member -NotePropertyName 'Warning' -NotePropertyValue 'Very limited path space remaining. Consider a shorter destination path.'
    }
    elseif ($availableChars -lt 200) {
        $result | Add-Member -NotePropertyName 'Note' -NotePropertyValue 'Limited path space. Deep folder structures may exceed limits.'
    }

    return $result
}

function Test-SharePointUrl {
    <#
    .SYNOPSIS
        Validates a SharePoint Online URL format.

    .DESCRIPTION
        Checks if the provided URL is a valid SharePoint Online URL format.

    .PARAMETER Url
        The URL to validate.

    .OUTPUTS
        Boolean indicating if URL is valid.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    # Basic URL validation
    if (-not ($Url -match '^https?://')) {
        return $false
    }

    try {
        $uri = [System.Uri]::new($Url)
    }
    catch {
        return $false
    }

    # Check for SharePoint domain patterns
    $validPatterns = @(
        '\.sharepoint\.com$'
        '\.sharepoint\.us$'           # GCC
        '\.sharepoint\.de$'           # Germany
        '\.sharepoint-mil\.us$'       # DoD
        '\.sharepoint\.cn$'           # China
    )

    foreach ($pattern in $validPatterns) {
        if ($uri.Host -match $pattern) {
            return $true
        }
    }

    # Also allow on-premises SharePoint URLs (any domain)
    # User can override validation if needed
    return $true
}

function ConvertTo-SharePointPath {
    <#
    .SYNOPSIS
        Converts a local file path to its SharePoint equivalent.

    .DESCRIPTION
        Takes a local file path and the scan root, and returns what the
        path would be in SharePoint after migration.

    .PARAMETER LocalPath
        The local file path.

    .PARAMETER SourceRoot
        The root path being scanned.

    .PARAMETER DestinationUrl
        The SharePoint destination URL.

    .OUTPUTS
        The full SharePoint URL for the file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalPath,

        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$DestinationUrl
    )

    # Get relative path
    $relativePath = $LocalPath.Substring($SourceRoot.TrimEnd('\', '/').Length)
    $relativePath = $relativePath.TrimStart('\', '/')

    # Convert backslashes to forward slashes
    $relativePath = $relativePath.Replace('\', '/')

    # Build SharePoint URL
    $destinationUrl = $DestinationUrl.TrimEnd('/')
    $sharePointUrl = "$destinationUrl/$relativePath"

    return $sharePointUrl
}

@{
    # Problematic File Types for SharePoint Online
    # These files will upload but have known issues with syncing, collaboration, or functionality

    # CAD Files - Severe collaboration issues (no file locking)
    CAD = @{
        Extensions = @(
            '.dwg', '.dxf', '.dwl', '.dwl2',           # AutoCAD
            '.rvt', '.rfa', '.rte', '.rft',             # Revit
            '.dgn',                                      # MicroStation
            '.sldprt', '.sldasm', '.slddrw',            # SolidWorks
            '.ipt', '.iam', '.idw', '.ipn',             # Inventor
            '.catpart', '.catproduct', '.catdrawing',   # CATIA
            '.prt', '.asm', '.drw',                     # Creo/Pro-E
            '.step', '.stp', '.iges', '.igs'            # CAD interchange
        )
        Severity = 'Warning'
        Category = 'CAD/BIM'
        Message = 'CAD files lack proper file locking in SharePoint. Multiple users can edit simultaneously without warning, causing data loss. Consider Autodesk Docs or dedicated file server for collaborative CAD work.'
    }

    # Adobe Creative Suite - Path and linking issues
    Adobe = @{
        Extensions = @(
            '.psd', '.psb',                    # Photoshop
            '.ai',                              # Illustrator
            '.indd', '.indt', '.idml',         # InDesign
            '.prproj', '.prel',                # Premiere Pro
            '.aep', '.aet',                    # After Effects
            '.fla', '.xfl',                    # Animate
            '.xd',                              # XD
            '.idlk'                             # InDesign lock files
        )
        Severity = 'Warning'
        Category = 'Adobe Creative'
        Message = 'Adobe files cannot be opened directly from SharePoint. InDesign/Premiere linked files will break due to user-specific sync paths. Users must download to local drive first.'
    }

    # Database Files - Corruption risk with multi-user access
    Database = @{
        Extensions = @(
            '.mdb', '.accdb', '.accde', '.accdr', '.laccdb',  # Microsoft Access
            '.qbw', '.qbb', '.qbm', '.qbx',                    # QuickBooks
            '.nsf', '.ntf',                                     # Lotus Notes
            '.sqlite', '.sqlite3', '.db', '.db3',              # SQLite
            '.dbf', '.fpt', '.cdx',                            # dBASE/FoxPro
            '.mdf', '.ldf', '.ndf',                            # SQL Server (should never be here!)
            '.fp7', '.fmp12'                                   # FileMaker
        )
        Severity = 'Warning'
        Category = 'Database'
        Message = 'Database files require exclusive access and may corrupt when synced by multiple users. Migrate to cloud-native database solutions (SharePoint Lists, Power Apps, SQL Azure).'
    }

    # Email Archive Files - Sync issues
    EmailArchive = @{
        Extensions = @('.pst', '.ost')
        Severity = 'Warning'
        Category = 'Email Archive'
        Message = 'PST files sync poorly - locked while Outlook runs and entire file (often 10-50GB) must re-upload after any change. Migrate to Exchange Online archive.'
        SizeWarningBytes = 1073741824  # 1 GB - extra warning for large PST
    }

    # Large Media Files - Performance issues
    LargeMedia = @{
        Extensions = @(
            '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.m4v', '.webm', '.flv',  # Video
            '.wav', '.aiff', '.aif', '.flac',                                  # Uncompressed audio
            '.raw', '.cr2', '.cr3', '.nef', '.arw', '.dng', '.orf', '.rw2'    # Camera RAW
        )
        Severity = 'Info'
        Category = 'Large Media'
        Message = 'Large media files may experience slow sync. Consider Microsoft Stream for video hosting.'
        SizeThresholdBytes = 5368709120  # 5 GB
    }

    # Development Folders - Too many files
    Development = @{
        FolderPatterns = @(
            'node_modules',
            '.git',
            '__pycache__',
            '.vs',
            '.idea',
            '.vscode',
            'bin',
            'obj',
            'packages',
            'vendor',
            '.nuget',
            'bower_components',
            '.gradle',
            'target',
            'build',
            'dist'
        )
        Severity = 'Warning'
        Category = 'Development'
        Message = 'Development folders contain many small files that can exceed sync limits (100K files). Exclude from migration.'
    }

    # Files with Secrets - Security risk
    Secrets = @{
        Patterns = @(
            '.env',
            '.env.*',
            'credentials.json',
            'secrets.json',
            'secrets.yaml',
            'secrets.yml',
            '*.pem',
            '*.key',
            '*.pfx',
            '*.p12',
            'id_rsa',
            'id_rsa.*',
            'id_ed25519',
            'id_ed25519.*',
            '.htpasswd',
            'wp-config.php',
            'web.config'
        )
        Severity = 'Warning'
        Category = 'Security'
        Message = 'This file may contain secrets or credentials. Review before migrating to shared storage.'
    }

    # Lock Files - Sync blockers
    LockFiles = @{
        Extensions = @('.dwl', '.dwl2', '.idlk', '.laccdb', '.ldb')
        Patterns = @('~$*', '.~*', '~*.tmp')
        Severity = 'Info'
        Category = 'Lock Files'
        Message = 'Lock files block OneDrive sync while parent application is open. These will typically be skipped during migration.'
    }

    # Bluebeam specific (PDF with path concerns)
    Bluebeam = @{
        Extensions = @('.pdf')
        PathThresholdChars = 200  # Bluebeam has 260 char limit, warn early
        Severity = 'Info'
        Category = 'Bluebeam'
        Message = 'Bluebeam Revu has a 260-character path limit (stricter than SharePoint). Long paths may cause issues when opening in Bluebeam.'
        OnlyWarnOnLongPaths = $true
    }

    # Virtual Machine and Disk Images
    VirtualMachine = @{
        Extensions = @(
            '.vmdk', '.vhd', '.vhdx', '.vdi',           # VM disk images
            '.iso', '.img', '.dmg',                      # Disk images
            '.ova', '.ovf',                              # VM exports
            '.qcow', '.qcow2'                            # QEMU images
        )
        Severity = 'Warning'
        Category = 'Virtual Machine'
        Message = 'Virtual machine and disk images are very large and cannot be used directly from SharePoint. Consider Azure blob storage for VM images.'
    }

    # Backup Files
    Backup = @{
        Extensions = @(
            '.bak', '.backup',
            '.old', '.orig',
            '.zip', '.7z', '.rar', '.tar', '.gz', '.tgz', '.tar.gz',  # Large archives
            '.cab', '.arc'
        )
        Severity = 'Info'
        Category = 'Backup/Archive'
        Message = 'Backup and archive files work but cannot be previewed in SharePoint. Consider if these need to be migrated or archived separately.'
        SizeThresholdBytes = 10737418240  # 10 GB
    }

    # OneNote (legacy sections)
    OneNote = @{
        Extensions = @('.one', '.onetoc2')
        Severity = 'Info'
        Category = 'OneNote'
        Message = 'OneNote section files should be migrated to OneNote Online notebooks instead of raw file migration.'
    }

    # Other Noteworthy Files
    Other = @{
        Extensions = @{
            '.lnk' = 'Windows shortcuts - paths may break after migration'
            '.url' = 'Internet shortcuts - generally work but verify links'
            '.gdoc' = 'Google Docs link - just a link file, no actual content'
            '.gsheet' = 'Google Sheets link - just a link file, no actual content'
            '.gslides' = 'Google Slides link - just a link file, no actual content'
            '.numbers' = 'Apple Numbers - no preview or collaboration in SharePoint'
            '.pages' = 'Apple Pages - no preview or collaboration in SharePoint'
            '.key' = 'Apple Keynote - no preview or collaboration in SharePoint'
            '.vsdx' = 'Visio - limited web viewing, requires Visio license'
            '.mpp' = 'MS Project - no web editing, requires Project license'
            '.pub' = 'Publisher - no web editing or preview'
        }
        Severity = 'Info'
        Category = 'Other'
        Message = 'This file type has limited functionality in SharePoint Online.'
    }
}

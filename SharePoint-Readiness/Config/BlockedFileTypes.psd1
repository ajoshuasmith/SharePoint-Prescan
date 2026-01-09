@{
    # Blocked File Types for SharePoint Online
    # These file types are blocked by default or commonly blocked by administrators

    # Executables - commonly blocked for security
    Executables = @{
        Extensions = @('.exe', '.bat', '.cmd', '.com', '.scr', '.pif', '.msi', '.msp', '.application')
        Severity = 'Warning'
        Message = 'Executable files are often blocked by SharePoint administrators for security reasons.'
    }

    # Scripts - commonly blocked for security
    Scripts = @{
        Extensions = @('.vbs', '.vbe', '.js', '.jse', '.wsf', '.wsh', '.ps1', '.psm1', '.psd1', '.ps1xml', '.csh', '.ksh')
        Severity = 'Warning'
        Message = 'Script files may be blocked by SharePoint administrators for security reasons.'
    }

    # System DLLs and drivers
    System = @{
        Extensions = @('.dll', '.sys', '.drv', '.cpl', '.ocx')
        Severity = 'Warning'
        Message = 'System files (.dll, .sys) are typically blocked in SharePoint Online.'
    }

    # Potentially dangerous file types
    Dangerous = @{
        Extensions = @(
            '.ade', '.adp', '.app', '.asa', '.asp', '.aspx', '.bas', '.cer', '.chm', '.class',
            '.cnt', '.crt', '.csh', '.der', '.fxp', '.gadget', '.grp', '.hlp', '.hpj', '.hta',
            '.htc', '.htr', '.htw', '.ida', '.idc', '.idq', '.ins', '.isp', '.its', '.jar',
            '.jse', '.ksh', '.lnk', '.mad', '.maf', '.mag', '.mam', '.maq', '.mar', '.mas',
            '.mat', '.mau', '.mav', '.maw', '.mcf', '.mda', '.mdb', '.mde', '.mdt', '.mdw',
            '.mdz', '.mht', '.mhtml', '.msc', '.msh', '.msh1', '.msh1xml', '.msh2', '.msh2xml',
            '.mshxml', '.msp', '.mst', '.ops', '.pcd', '.pif', '.plg', '.prf', '.prg', '.printer',
            '.pst', '.reg', '.rem', '.scf', '.scr', '.sct', '.shb', '.shs', '.shtm', '.shtml',
            '.soap', '.stm', '.svc', '.url', '.vb', '.vbe', '.vbs', '.vsix', '.ws', '.wsc',
            '.wsf', '.wsh', '.xamlx'
        )
        Severity = 'Warning'
        Message = 'This file type may be blocked by SharePoint for security reasons.'
    }

    # Files that won't sync properly
    NoSync = @{
        Patterns = @('desktop.ini', '.ds_store', 'thumbs.db', '.spotlight-*', '.trashes', '.fseventsd')
        Severity = 'Info'
        Message = 'System files that typically do not sync to SharePoint/OneDrive.'
    }

    # Temporary files
    Temporary = @{
        Extensions = @('.tmp', '.temp', '.bak', '.swp', '.swo')
        Patterns = @('~*', '*.~*')
        Severity = 'Info'
        Message = 'Temporary files are typically not synced to SharePoint.'
    }
}

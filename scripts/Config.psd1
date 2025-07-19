# VM Setup Configuration
# This file contains configuration settings for the VM post-initialization setup

@{
    # Storage Configuration
    Storage = @{
        # Storage pool and virtual disk settings
        PoolName = "VMStoragePool"
        VirtualDiskName = "VMStripedDisk"
        
        # Volume settings
        Volume1 = @{
            Label = "Data"
            SizePercent = 50  # Percentage of total disk space
        }
        Volume2 = @{
            Label = "Applications"
            SizePercent = 50  # Remaining space
        }
        
        # Minimum number of disks required for striping
        MinimumDisks = 2
    }
    
    # Windows Updates Configuration
    WindowsUpdates = @{
        # Whether to automatically reboot after updates if required
        AutoReboot = $false
        
        # Whether to install optional updates
        IncludeOptional = $false
        
        # Maximum time to wait for updates (in minutes)
        TimeoutMinutes = 60
    }
    
    # Parsec Configuration
    Parsec = @{
        # Download URL for Parsec (leave empty to use default)
        DownloadUrl = ""
        
        # Custom download path (leave empty to use temp directory)
        DownloadPath = ""
        
        # Installation arguments
        InstallArgs = "/S"  # Silent installation
    }
    
    # Logging Configuration
    Logging = @{
        # Enable detailed logging
        Verbose = $true
        
        # Log file path (leave empty to not create log file)
        LogFile = ""
        
        # Whether to display timestamps
        ShowTimestamps = $true
    }
    
    # General Configuration
    General = @{
        # Whether to continue on non-critical errors
        ContinueOnError = $true
        
        # Timeout for network operations (in seconds)
        NetworkTimeout = 30
        
        # Whether to clean up temporary files
        CleanupTempFiles = $true
    }
}

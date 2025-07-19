# VM Setup Configuration - Modular Edition
# This file contains configuration settings for the VM post-initialization setup

@{
    # Storage Configuration (for Storage Spaces feature)
    Storage = @{
        # Storage pool and virtual disk settings
        PoolName = "VMStoragePool"
        VirtualDiskName = "VMStripedDisk"
        
        # Volume settings
        Volume1Label = "Data"
        Volume2Label = "Applications"
        Volume1SizePercent = 50  # Percentage of total disk space for first volume
        
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
        
        # Maximum number of retry attempts
        MaxRetries = 3
    }
    
    # Parsec Configuration
    Parsec = @{
        # Download URL for Parsec (leave empty to use default)
        DownloadUrl = "https://builds.parsec.app/package/parsec-windows.exe"
        
        # Custom download path (leave empty to use temp directory)
        DownloadPath = ""
        
        # Installation arguments
        InstallArgs = "/S"  # Silent installation
        
        # Timeout for download (in seconds)
        TimeoutSeconds = 300
        
        # Whether to clean up installer after installation
        CleanupInstaller = $true
        
        # Whether to validate installation success
        ValidateInstallation = $true
    }
    
    # Logging Configuration
    Logging = @{
        # Enable detailed logging
        Verbose = $true
        
        # Log file path (leave empty to not create log file)
        LogFile = ""
        
        # Whether to display timestamps in log messages
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
        
        # Features directory (relative to script directory)
        FeaturesDirectory = "features"
    }
    
    # Feature-specific settings
    Features = @{
        # Default execution order (if not using filename-based ordering)
        ExecutionOrder = @(
            "01-storage-spaces.ps1",
            "02-windows-updates.ps1", 
            "03-parsec.ps1"
        )
        
        # Features to skip (by filename or feature name)
        Skip = @()
        
        # Features to include (empty means include all)
        Include = @()
    }
}

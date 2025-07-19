# Test Configuration for VM Setup Scripts
# This configuration is used for testing purposes

@{
    # Storage Configuration - Test Settings
    Storage = @{
        PoolName = "TestStoragePool"
        VirtualDiskName = "TestStripedDisk"
        Volume1Label = "TestData"
        Volume2Label = "TestApps"
        Volume1SizePercent = 30
        Volume1FileSystem = "NTFS"  # Use NTFS for both in testing
        Volume2FileSystem = "NTFS"
        MinimumDisks = 2
    }
    
    # Windows Updates Configuration - Conservative settings for testing
    WindowsUpdates = @{
        AutoReboot = $false
        IncludeOptional = $false
        TimeoutMinutes = 30
        MaxRetries = 2
    }
    
    # Parsec Configuration - Test settings
    Parsec = @{
        DownloadUrl = "https://builds.parsec.app/package/parsec-windows.exe"
        DownloadPath = ""
        InstallArgs = "/S"
        TimeoutSeconds = 120  # Shorter timeout for testing
        CleanupInstaller = $true
        ValidateInstallation = $false  # Skip validation in tests
    }
    
    # .NET SDK Configuration - Test settings
    DotNetSDK = @{
        Version = "Latest"
        DownloadPath = ""
        InstallArgs = "/quiet /norestart"
        TimeoutSeconds = 300  # Shorter timeout for testing
        CleanupInstaller = $true
        ValidateInstallation = $false  # Skip validation in tests
        AddToPath = $true
    }
    
    # Source Directory Configuration - Test settings
    SourceDirectory = @{
        DirectoryName = "test-src"
        AddDefenderExclusion = $false  # Don't modify Defender in tests
        CreateIfMissing = $true
        Subdirectories = @("test-github", "test-projects")
        Permissions = ""
    }
    
    # Logging Configuration - Verbose for testing
    Logging = @{
        Verbose = $true
        LogFile = ""
        ShowTimestamps = $true
    }
    
    # General Configuration - Fail-safe settings for testing
    General = @{
        ContinueOnError = $true
        NetworkTimeout = 15
        CleanupTempFiles = $true
        FeaturesDirectory = "features"
    }
    
    # Feature-specific settings - Test mode
    Features = @{
        ExecutionOrder = @(
            "01-storage-spaces.ps1",
            "05-source-directory.ps1"  # Only test safe features
        )
        Skip = @(
            "02-windows-updates.ps1",  # Skip potentially disruptive features
            "03-parsec.ps1",
            "04-dotnet-sdk9.ps1"
        )
        Include = @()
    }
}

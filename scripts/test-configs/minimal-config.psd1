# Minimal Test Configuration
# Used for testing configuration loading with minimal settings

@{
    Storage = @{
        Volume1FileSystem = "ReFS"
        Volume2FileSystem = "NTFS"
    }
    
    General = @{
        ContinueOnError = $true
    }
    
    Logging = @{
        Verbose = $false
    }
}

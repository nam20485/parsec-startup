# VM Post-Initialization Setup Scripts - Modular Edition

This repository contains a modular PowerShell framework for automating VM setup tasks after initialization. The system automatically discovers and executes feature scripts from the features directory.

## Overview

The modular setup framework provides:

1. **Automatic Feature Discovery**: Scans the features directory for PowerShell scripts
2. **Feature-based Installation**: Each feature is self-contained with its own prerequisites and installation logic
3. **Flexible Execution**: Run all features, specific features, or exclude certain features
4. **Comprehensive Logging**: Detailed output with timestamps and status tracking
5. **Error Handling**: Continue on errors or stop at first failure

## Default Features

The framework includes these built-in features:

### 01-storage-spaces.ps1

- **Purpose**: Creates a striped virtual disk with two volumes using Windows Storage Spaces
- **Requirements**: Administrator privileges, Storage Spaces support, minimum 2 physical disks
- **Output**: Two formatted volumes for data and applications

### 02-windows-updates.ps1  

- **Purpose**: Downloads and installs all available Windows updates
- **Requirements**: Administrator privileges, internet connectivity, Windows Update service
- **Output**: Fully updated Windows system (may require reboot)

### 03-parsec.ps1

- **Purpose**: Downloads and installs Parsec for remote desktop access
- **Requirements**: Administrator privileges, internet connectivity
- **Output**: Installed and configured Parsec application

### 04-dotnet-sdk9.ps1

- **Purpose**: Downloads and installs the latest .NET SDK 9
- **Requirements**: Administrator privileges, internet connectivity
- **Output**: Installed .NET SDK 9 with development tools and runtime

## File Structure

```text
scripts/
├── startup.ps1              # Main modular startup script
├── Config.psd1             # Configuration file
├── Test-VMSetup.ps1         # Test/validation script
├── VMSetupModule.psm1       # Legacy module (deprecated)
└── features/
    ├── 01-storage-spaces.ps1
    ├── 02-windows-updates.ps1
    ├── 03-parsec.ps1
    └── 04-dotnet-sdk9.ps1
```

## Usage

### Basic Usage

Run all features in order:

```powershell
# Navigate to the scripts directory
cd "C:\Users\nmiller\src\github\nam20485\parsec-startup\scripts"

# Run all features
.\startup.ps1
```

### Advanced Usage

```powershell
# List all available features
.\startup.ps1 -ListFeatures

# Dry run (show what would be executed without actually running)
.\startup.ps1 -DryRun

# Run only specific features
.\startup.ps1 -IncludeFeatures @("01-storage-spaces.ps1", "03-parsec.ps1")

# Exclude specific features
.\startup.ps1 -ExcludeFeatures @("02-windows-updates.ps1")

# Use custom configuration file
.\startup.ps1 -ConfigFile "C:\path\to\custom-config.psd1"

# Stop on first error instead of continuing
.\startup.ps1 -ContinueOnError:$false

# Run a single feature directly
.\features\03-parsec.ps1
```

## Creating Custom Features

To create a new feature, create a PowerShell script in the `features` directory with this structure:

```powershell
# Feature: Your Feature Name
# Description of what this feature does

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [hashtable]$Config = @{}
)

# Feature metadata
$FeatureInfo = @{
    Name = "Your Feature Name"
    Description = "Description of what this feature does"
    Version = "1.0.0"
    RequiresReboot = $false
    Prerequisites = @("List", "of", "prerequisites")
}

function Test-FeaturePrerequisites {
    [CmdletBinding()]
    param()
    
    $issues = @()
    
    # Add your prerequisite checks here
    # Return array of issue descriptions (empty array = all good)
    
    return $issues
}

function Install-Feature {
    [CmdletBinding()]
    param(
        [hashtable]$Config = @{}
    )
    
    try {
        # Your installation logic here
        
        return @{
            Success = $true
            Message = "Feature installed successfully"
            Data = @{
                # Any additional data about the installation
            }
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Installation failed: $($_.Exception.Message)"
            Error = $_
        }
    }
}

# Support for direct execution
if ($MyInvocation.InvocationName -ne '.') {
    # Script is being executed directly
    Write-Host "Your Feature Name - $($FeatureInfo.Name)" -ForegroundColor Cyan
    
    $prereqIssues = Test-FeaturePrerequisites
    if ($prereqIssues.Count -gt 0) {
        Write-Warning "Prerequisites not met:"
        $prereqIssues | ForEach-Object { Write-Warning "- $_" }
        exit 1
    }
    
    $result = Install-Feature -Config $Config
    if ($result.Success) {
        Write-Host $result.Message -ForegroundColor Green
        exit 0
    }
    else {
        Write-Error $result.Message
        exit 1
    }
}
```

### Feature Naming Convention

- Use numeric prefixes to control execution order: `01-`, `02-`, `03-`, etc.
- Use descriptive names: `01-storage-spaces.ps1`, `02-windows-updates.ps1`
- Features are executed in alphabetical order by filename

## Configuration

Edit `Config.psd1` to customize behavior:

```powershell
@{
    Storage = @{
        PoolName = "CustomStoragePool"
        Volume1Label = "CustomData"
        # ... other storage settings
    }
    
    WindowsUpdates = @{
        AutoReboot = $true
        IncludeOptional = $true
        # ... other update settings
    }
    
    Parsec = @{
        DownloadUrl = "https://custom.url/parsec.exe"
        # ... other Parsec settings
    }
    
    DotNetSDK = @{
        Version = "9.0.100"  # or "Latest"
        InstallArgs = "/quiet /norestart"
        # ... other .NET SDK settings
    }
    
    Logging = @{
        LogFile = "C:\Logs\vm-setup.log"
        ShowTimestamps = $true
    }
    
    Features = @{
        Skip = @("02-windows-updates.ps1")  # Skip Windows Updates
        Include = @()  # Include all (default)
    }
}
```

## Prerequisites

- Windows Server or Windows 10/11
- PowerShell 5.1 or later  
- Administrator privileges
- Internet connectivity
- Appropriate hardware for specific features (e.g., multiple disks for Storage Spaces)

## Error Handling

The framework provides robust error handling:

- **Prerequisites Validation**: Each feature validates its requirements before execution
- **Continue on Error**: By default, continues executing remaining features if one fails
- **Detailed Logging**: Comprehensive error messages with context
- **Rollback Support**: Features can implement their own rollback logic
- **Dry Run Mode**: Test what would be executed without making changes

## Logging

The system provides detailed logging with:

- **Timestamped Messages**: Optional timestamps on all log entries
- **Color-coded Output**: Different colors for different message types
- **File Logging**: Optional logging to file
- **Progress Tracking**: Clear indication of current feature being executed
- **Summary Report**: Comprehensive summary at completion

## Troubleshooting

### Common Issues

1. **"Script must be run as Administrator"**
   - Right-click PowerShell and select "Run as Administrator"

2. **"Features directory not found"**
   - Ensure the `features` directory exists in the same folder as `startup.ps1`
   - Check that feature scripts have `.ps1` extension

3. **"PowerShell execution policy is Restricted"**
   - Run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

4. **Feature-specific errors**
   - Run individual features directly to isolate issues
   - Check feature prerequisites with the test script
   - Review feature-specific error messages

### Manual Recovery

If the framework fails:

1. **Check the summary output** to see which features completed
2. **Run individual features** directly to isolate problems
3. **Use dry run mode** to test without making changes
4. **Check prerequisites** with the test script
5. **Review configuration** for any mismatched settings

### Testing

Use the test script to validate the environment:

```powershell
.\Test-VMSetup.ps1
```

This will check:

- Prerequisites for all features
- Available hardware resources
- Network connectivity
- Module dependencies

## Migration from Legacy Version

If migrating from the legacy monolithic version:

1. **Backup** your existing scripts
2. **Update** any custom configurations to the new format
3. **Test** with dry run mode first
4. **Migrate** any custom logic to new feature scripts

The legacy `VMSetupModule.psm1` is kept for backward compatibility but is deprecated.

## Support

For issues or questions:

1. Use dry run mode to test safely
2. Check individual feature logs for specific errors  
3. Validate prerequisites with the test script
4. Review the feature script source code for implementation details
5. Check PowerShell execution policy and permissions

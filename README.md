# VM Post-Initialization Setup Scripts

This repository contains PowerShell scripts for automating VM setup tasks after initialization.

## Overview

The setup process includes:
1. **Storage Configuration**: Creates a striped virtual disk with two volumes using Windows Storage Spaces
2. **Windows Updates**: Downloads and installs all available Windows updates
3. **Parsec Installation**: Downloads and installs Parsec for remote desktop access

## Files

- `startup.ps1` - Main script that orchestrates the setup process
- `VMSetupModule.psm1` - PowerShell module containing all setup functions
- `Config.psd1` - Configuration file for customizing setup behavior

## Prerequisites

- Windows Server or Windows 10/11 with Storage Spaces support
- PowerShell 5.1 or later
- Administrator privileges
- Internet connectivity
- At least 2 physical disks available for striping (for storage setup)

## Usage

### Basic Usage

Run the main script as Administrator:

```powershell
# Navigate to the scripts directory
cd "C:\Users\nmiller\src\github\nam20485\parsec-startup\scripts"

# Run the setup script
.\startup.ps1
```

### Advanced Usage

You can customize the behavior by modifying `Config.psd1` or by importing the module and calling functions individually:

```powershell
# Import the module
Import-Module ".\VMSetupModule.psm1"

# Check prerequisites first
Test-Prerequisites

# Create striped virtual disk with custom settings
New-StripedVirtualDisk -PoolName "CustomPool" -VirtualDiskName "CustomDisk" -Volume1Label "DataDrive" -Volume2Label "AppDrive"

# Install Windows updates without auto-reboot
Install-WindowsUpdates -AutoReboot $false

# Install Parsec
Install-Parsec
```

## Functions Available in VMSetupModule

### `Test-Prerequisites`
Checks if all prerequisites are met (admin privileges, internet connectivity, Storage Spaces availability).

### `New-StripedVirtualDisk`
Creates a striped virtual disk with two volumes using Storage Spaces.

**Parameters:**
- `PoolName` - Name for the storage pool (default: "VMStoragePool")
- `VirtualDiskName` - Name for the virtual disk (default: "VMStripedDisk") 
- `Volume1Label` - Label for first volume (default: "Data")
- `Volume2Label` - Label for second volume (default: "Apps")

### `Install-WindowsUpdates`
Downloads and installs all available Windows updates.

**Parameters:**
- `AutoReboot` - Whether to automatically reboot if required (default: false)

### `Install-Parsec`
Downloads and installs Parsec silently.

**Parameters:**
- `DownloadPath` - Path to download installer (default: temp directory)

### `Write-SetupSummary`
Displays a summary of the setup process results.

## Configuration

Edit `Config.psd1` to customize:

- Storage pool and volume names
- Volume size distribution
- Windows Update behavior
- Parsec installation settings
- Logging preferences

## Error Handling

The scripts include comprehensive error handling:
- Prerequisites are checked before starting
- Each step is tracked and reported
- Failed steps are clearly identified
- Partial completion is supported

## Logging

The scripts provide detailed console output with:
- Color-coded status messages
- Progress indicators
- Error details
- Completion summary

## Troubleshooting

### Common Issues

1. **"Script must be run as Administrator"**
   - Right-click PowerShell and select "Run as Administrator"

2. **"At least 2 physical disks are required for striping"**
   - Ensure your VM has multiple virtual disks attached
   - Check that disks are available for pooling with `Get-PhysicalDisk`

3. **"No internet connectivity detected"**
   - Verify network configuration in the VM
   - Check firewall settings

4. **Windows Updates fail to install**
   - Ensure Windows Update service is running
   - Check available disk space
   - Verify internet connectivity

### Manual Recovery

If the script fails partway through, you can:

1. Check what completed successfully in the summary
2. Import the module and run individual functions
3. Review error messages and address specific issues
4. Re-run the main script (it will skip already completed steps where possible)

## Security Considerations

- The script requires Administrator privileges
- Downloads are performed over HTTPS
- Parsec installer is downloaded from the official source
- No sensitive data is stored or transmitted

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review PowerShell error messages
3. Ensure all prerequisites are met
4. Test individual functions to isolate problems

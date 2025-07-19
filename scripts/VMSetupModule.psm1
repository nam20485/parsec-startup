# VMSetupModule.psm1
# PowerShell module for VM post-initialization setup tasks

#Requires -RunAsAdministrator

function New-StripedVirtualDisk {
    <#
    .SYNOPSIS
    Creates a striped virtual disk with two volumes in Storage Spaces
    
    .DESCRIPTION
    Creates a storage pool, virtual disk, and two volumes for the VM
    
    .PARAMETER PoolName
    Name for the storage pool
    
    .PARAMETER VirtualDiskName
    Name for the virtual disk
    
    .PARAMETER Volume1Label
    Label for the first volume
    
    .PARAMETER Volume2Label
    Label for the second volume
    
    .PARAMETER Volume1Size
    Size for the first volume (default: 50% of available space)
    
    .PARAMETER Volume2Size
    Size for the second volume (default: remaining space)
    #>
    [CmdletBinding()]
    param(
        [string]$PoolName = "VMStoragePool",
        [string]$VirtualDiskName = "VMStripedDisk",
        [string]$Volume1Label = "Data",
        [string]$Volume2Label = "Apps",
        [string]$Volume1Size = "50%",
        [string]$Volume2Size = "100%"
    )
    
    try {
        Write-Host "Creating striped virtual disk with Storage Spaces..." -ForegroundColor Green
        
        # Get available physical disks (excluding system disk)
        $physicalDisks = Get-PhysicalDisk | Where-Object { $_.CanPool -eq $true }
        
        if ($physicalDisks.Count -lt 2) {
            Write-Warning "At least 2 physical disks are required for striping. Found: $($physicalDisks.Count)"
            return $false
        }
        
        # Create storage pool
        Write-Host "Creating storage pool: $PoolName"
        $storagePool = New-StoragePool -FriendlyName $PoolName -StorageSubSystemFriendlyName "Windows Storage*" -PhysicalDisks $physicalDisks
        
        # Create virtual disk with striping
        Write-Host "Creating virtual disk: $VirtualDiskName"
        $virtualDisk = New-VirtualDisk -StoragePoolFriendlyName $PoolName -FriendlyName $VirtualDiskName -ResiliencySettingName "Simple" -UseMaximumSize
        
        # Initialize and partition the disk
        $disk = Get-Disk | Where-Object { $_.FriendlyName -eq $VirtualDiskName }
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT
        
        # Create first partition (50% of space)
        Write-Host "Creating first volume: $Volume1Label"
        $partition1 = New-Partition -DiskNumber $disk.Number -UseMaximumSize
        $volume1 = Format-Volume -Partition $partition1 -FileSystem NTFS -NewFileSystemLabel $Volume1Label -Confirm:$false
        
        # Resize first partition to 50% and create second partition
        $totalSize = (Get-Disk -Number $disk.Number).Size
        $partition1Size = [math]::Floor($totalSize * 0.5)
        
        Resize-Partition -DiskNumber $disk.Number -PartitionNumber $partition1.PartitionNumber -Size $partition1Size
        
        Write-Host "Creating second volume: $Volume2Label"
        $partition2 = New-Partition -DiskNumber $disk.Number -UseMaximumSize
        $volume2 = Format-Volume -Partition $partition2 -FileSystem NTFS -NewFileSystemLabel $Volume2Label -Confirm:$false
        
        Write-Host "Striped virtual disk created successfully!" -ForegroundColor Green
        Write-Host "Volume 1 ($Volume1Label): $($volume1.DriveLetter):" -ForegroundColor Cyan
        Write-Host "Volume 2 ($Volume2Label): $($volume2.DriveLetter):" -ForegroundColor Cyan
        
        return $true
    }
    catch {
        Write-Error "Failed to create striped virtual disk: $($_.Exception.Message)"
        return $false
    }
}

function Install-WindowsUpdates {
    <#
    .SYNOPSIS
    Installs all available Windows updates
    
    .DESCRIPTION
    Downloads and installs all available Windows updates using PSWindowsUpdate module
    
    .PARAMETER AutoReboot
    Whether to automatically reboot if required
    #>
    [CmdletBinding()]
    param(
        [bool]$AutoReboot = $false
    )
    
    try {
        Write-Host "Installing Windows Updates..." -ForegroundColor Green
        
        # Install PSWindowsUpdate module if not present
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Host "Installing PSWindowsUpdate module..."
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
            Install-Module -Name PSWindowsUpdate -Force -AllowClobber
        }
        
        Import-Module PSWindowsUpdate
        
        # Get available updates
        Write-Host "Checking for available updates..."
        $updates = Get-WUList
        
        if ($updates.Count -eq 0) {
            Write-Host "No updates available." -ForegroundColor Yellow
            return $true
        }
        
        Write-Host "Found $($updates.Count) updates. Installing..." -ForegroundColor Cyan
        
        # Install updates
        $installResult = Install-WindowsUpdate -AcceptAll -AutoReboot:$AutoReboot -Confirm:$false
        
        if ($installResult) {
            Write-Host "Windows updates installed successfully!" -ForegroundColor Green
            
            # Check if reboot is required
            if (Get-WURebootStatus -Silent) {
                Write-Warning "A reboot is required to complete the installation."
                if ($AutoReboot) {
                    Write-Host "Rebooting in 10 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 10
                    Restart-Computer -Force
                }
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to install Windows updates: $($_.Exception.Message)"
        return $false
    }
}

function Install-Parsec {
    <#
    .SYNOPSIS
    Downloads and installs Parsec
    
    .DESCRIPTION
    Downloads the latest Parsec installer and installs it silently
    
    .PARAMETER DownloadPath
    Path to download the installer
    #>
    [CmdletBinding()]
    param(
        [string]$DownloadPath = "$env:TEMP\parsec-windows.exe"
    )
    
    try {
        Write-Host "Installing Parsec..." -ForegroundColor Green
        
        # Parsec download URL
        $parsecUrl = "https://builds.parsec.app/package/parsec-windows.exe"
        
        # Download Parsec installer
        Write-Host "Downloading Parsec installer..."
        Invoke-WebRequest -Uri $parsecUrl -OutFile $DownloadPath -UseBasicParsing
        
        if (-not (Test-Path $DownloadPath)) {
            throw "Failed to download Parsec installer"
        }
        
        # Install Parsec silently
        Write-Host "Installing Parsec..."
        $process = Start-Process -FilePath $DownloadPath -ArgumentList "/S" -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Parsec installed successfully!" -ForegroundColor Green
            
            # Clean up installer
            Remove-Item -Path $DownloadPath -Force -ErrorAction SilentlyContinue
            
            return $true
        }
        else {
            throw "Parsec installation failed with exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-Error "Failed to install Parsec: $($_.Exception.Message)"
        return $false
    }
}

function Test-Prerequisites {
    <#
    .SYNOPSIS
    Tests if all prerequisites are met for the setup
    
    .DESCRIPTION
    Checks if running as administrator and has internet connectivity
    #>
    [CmdletBinding()]
    param()
    
    $issues = @()
    
    # Check if running as administrator
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $issues += "Script must be run as Administrator"
    }
    
    # Check internet connectivity
    try {
        $null = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 5
    }
    catch {
        $issues += "No internet connectivity detected"
    }
    
    # Check Storage Spaces availability
    try {
        $null = Get-StorageSubSystem -ErrorAction Stop
    }
    catch {
        $issues += "Storage Spaces not available"
    }
    
    if ($issues.Count -gt 0) {
        Write-Warning "Prerequisites check failed:"
        $issues | ForEach-Object { Write-Warning "- $_" }
        return $false
    }
    
    Write-Host "All prerequisites met!" -ForegroundColor Green
    return $true
}

function Write-SetupSummary {
    <#
    .SYNOPSIS
    Writes a summary of the setup process
    
    .DESCRIPTION
    Displays completion status and next steps
    
    .PARAMETER Results
    Hashtable containing results from each setup step
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Results
    )
    
    Write-Host "`n" + "="*50 -ForegroundColor Cyan
    Write-Host "VM Setup Summary" -ForegroundColor Cyan
    Write-Host "="*50 -ForegroundColor Cyan
    
    foreach ($step in $Results.Keys) {
        $status = if ($Results[$step]) { "✓ COMPLETED" } else { "✗ FAILED" }
        $color = if ($Results[$step]) { "Green" } else { "Red" }
        Write-Host "$step`: $status" -ForegroundColor $color
    }
    
    Write-Host "`nSetup completed at: $(Get-Date)" -ForegroundColor Cyan
    
    if ($Results.Values -contains $false) {
        Write-Warning "`nSome steps failed. Please review the errors above and retry if necessary."
    }
    else {
        Write-Host "`nAll setup steps completed successfully!" -ForegroundColor Green
        Write-Host "Your VM is ready for use." -ForegroundColor Green
    }
}

# Export functions
Export-ModuleMember -Function New-StripedVirtualDisk, Install-WindowsUpdates, Install-Parsec, Test-Prerequisites, Write-SetupSummary

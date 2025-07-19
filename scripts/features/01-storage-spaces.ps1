# Feature: Storage Spaces - Striped Virtual Disk Creation
# Creates a striped virtual disk with two volumes using Windows Storage Spaces

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [hashtable]$Config = @{}
)

# Feature metadata
$FeatureInfo = @{
    Name = "Storage Spaces Setup"
    Description = "Creates a striped virtual disk with two volumes using Windows Storage Spaces"
    Version = "1.0.0"
    RequiresReboot = $false
    Prerequisites = @("Administrator privileges", "Storage Spaces support", "Minimum 2 physical disks")
}

function Test-FeaturePrerequisites {
    [CmdletBinding()]
    param()
    
    $issues = @()
    
    # Check if running as administrator
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $issues += "Must be run as Administrator"
    }
    
    # Check Storage Spaces availability
    try {
        $null = Get-StorageSubSystem -ErrorAction Stop
    }
    catch {
        $issues += "Storage Spaces not available: $($_.Exception.Message)"
    }
    
    # Check available physical disks
    try {
        $physicalDisks = Get-PhysicalDisk | Where-Object { $_.CanPool -eq $true }
        if ($physicalDisks.Count -lt 2) {
            $issues += "At least 2 physical disks are required for striping. Found: $($physicalDisks.Count)"
        }
    }
    catch {
        $issues += "Error checking physical disks: $($_.Exception.Message)"
    }
    
    return $issues
}

function Install-Feature {
    [CmdletBinding()]
    param(
        [hashtable]$Config = @{}
    )
    
    # Default configuration
    $defaultConfig = @{
        PoolName = "VMStoragePool"
        VirtualDiskName = "VMStripedDisk"
        Volume1Label = "Data"
        Volume2Label = "Applications"
        Volume1SizePercent = 50
    }
    
    # Merge with provided config
    $featureConfig = $defaultConfig.Clone()
    if ($Config.Storage) {
        foreach ($key in $Config.Storage.Keys) {
            if ($featureConfig.ContainsKey($key)) {
                $featureConfig[$key] = $Config.Storage[$key]
            }
        }
    }
    
    try {
        Write-Host "Creating striped virtual disk with Storage Spaces..." -ForegroundColor Green
        
        # Get available physical disks (excluding system disk)
        $physicalDisks = Get-PhysicalDisk | Where-Object { $_.CanPool -eq $true }
        
        Write-Host "Found $($physicalDisks.Count) available disks for pooling:" -ForegroundColor Cyan
        $physicalDisks | ForEach-Object {
            Write-Host "  - $($_.FriendlyName) ($([math]::Round($_.Size / 1GB, 2)) GB)" -ForegroundColor Gray
        }
        
        # Create storage pool
        Write-Host "Creating storage pool: $($featureConfig.PoolName)" -ForegroundColor Cyan
        $storagePool = New-StoragePool -FriendlyName $featureConfig.PoolName -StorageSubSystemFriendlyName "Windows Storage*" -PhysicalDisks $physicalDisks
        
        # Create virtual disk with striping
        Write-Host "Creating virtual disk: $($featureConfig.VirtualDiskName)" -ForegroundColor Cyan
        $virtualDisk = New-VirtualDisk -StoragePoolFriendlyName $featureConfig.PoolName -FriendlyName $featureConfig.VirtualDiskName -ResiliencySettingName "Simple" -UseMaximumSize
        
        # Initialize and partition the disk
        $disk = Get-Disk | Where-Object { $_.FriendlyName -eq $featureConfig.VirtualDiskName }
        Write-Host "Initializing disk $($disk.Number)" -ForegroundColor Cyan
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT
        
        # Calculate sizes
        $totalSize = $disk.Size
        $volume1Size = [math]::Floor($totalSize * ($featureConfig.Volume1SizePercent / 100))
        
        # Create first partition
        Write-Host "Creating first volume: $($featureConfig.Volume1Label) ($([math]::Round($volume1Size / 1GB, 2)) GB)" -ForegroundColor Cyan
        $partition1 = New-Partition -DiskNumber $disk.Number -Size $volume1Size
        $volume1 = Format-Volume -Partition $partition1 -FileSystem NTFS -NewFileSystemLabel $featureConfig.Volume1Label -Confirm:$false
        
        # Create second partition with remaining space
        Write-Host "Creating second volume: $($featureConfig.Volume2Label)" -ForegroundColor Cyan
        $partition2 = New-Partition -DiskNumber $disk.Number -UseMaximumSize
        $volume2 = Format-Volume -Partition $partition2 -FileSystem NTFS -NewFileSystemLabel $featureConfig.Volume2Label -Confirm:$false
        
        # Assign drive letters if not automatically assigned
        if (-not $volume1.DriveLetter) {
            $volume1 | Get-Partition | Set-Partition -NewDriveLetter (Get-AvailableDriveLetter)
        }
        if (-not $volume2.DriveLetter) {
            $volume2 | Get-Partition | Set-Partition -NewDriveLetter (Get-AvailableDriveLetter)
        }
        
        Write-Host "Striped virtual disk created successfully!" -ForegroundColor Green
        Write-Host "Volume 1 ($($featureConfig.Volume1Label)): $($volume1.DriveLetter):" -ForegroundColor Green
        Write-Host "Volume 2 ($($featureConfig.Volume2Label)): $($volume2.DriveLetter):" -ForegroundColor Green
        
        return @{
            Success = $true
            Message = "Storage Spaces configured successfully"
            Data = @{
                PoolName = $featureConfig.PoolName
                VirtualDiskName = $featureConfig.VirtualDiskName
                Volume1 = @{
                    Label = $featureConfig.Volume1Label
                    DriveLetter = $volume1.DriveLetter
                    Size = $volume1Size
                }
                Volume2 = @{
                    Label = $featureConfig.Volume2Label
                    DriveLetter = $volume2.DriveLetter
                    Size = $partition2.Size
                }
            }
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to create striped virtual disk: $($_.Exception.Message)"
            Error = $_
        }
    }
}

function Get-AvailableDriveLetter {
    $usedLetters = Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { $_.DriveLetter }
    $allLetters = 'D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
    $availableLetter = $allLetters | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
    return $availableLetter
}

# Export feature information and functions
if ($MyInvocation.InvocationName -ne '.') {
    # Script is being executed directly, not dot-sourced
    Write-Host "Storage Spaces Feature - $($FeatureInfo.Name)" -ForegroundColor Cyan
    Write-Host "Description: $($FeatureInfo.Description)" -ForegroundColor Gray
    
    # Check prerequisites
    $prereqIssues = Test-FeaturePrerequisites
    if ($prereqIssues.Count -gt 0) {
        Write-Warning "Prerequisites not met:"
        $prereqIssues | ForEach-Object { Write-Warning "- $_" }
        exit 1
    }
    
    # Install feature
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

# VM Post-Initialization Startup Script
# This script runs after the VM is initialized and performs the following tasks:
# 1. Creates a striped virtual disk with two volumes in Storage Spaces
# 2. Installs all Windows updates
# 3. Installs Parsec

#Requires -RunAsAdministrator

# Import the VM Setup module
$moduleDir = $PSScriptRoot
Import-Module "$moduleDir\VMSetupModule.psm1" -Force

# Initialize results tracking
$results = @{
    "Prerequisites Check" = $false
    "Striped Virtual Disk Creation" = $false
    "Windows Updates Installation" = $false
    "Parsec Installation" = $false
}

# Script configuration
$config = @{
    StoragePool = @{
        PoolName = "VMStoragePool"
        VirtualDiskName = "VMStripedDisk"
        Volume1Label = "Data"
        Volume2Label = "Applications"
    }
    WindowsUpdates = @{
        AutoReboot = $false  # Set to $true if you want automatic reboot
    }
}

try {
    Write-Host "Starting VM post-initialization setup..." -ForegroundColor Cyan
    Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
    Write-Host ""
    
    # Step 1: Check prerequisites
    Write-Host "Step 1: Checking prerequisites..." -ForegroundColor Yellow
    $results["Prerequisites Check"] = Test-Prerequisites
    
    if (-not $results["Prerequisites Check"]) {
        throw "Prerequisites check failed. Cannot continue with setup."
    }
    
    Write-Host ""
    
    # Step 2: Create striped virtual disk with two volumes
    Write-Host "Step 2: Creating striped virtual disk with Storage Spaces..." -ForegroundColor Yellow
    $results["Striped Virtual Disk Creation"] = New-StripedVirtualDisk -PoolName $config.StoragePool.PoolName -VirtualDiskName $config.StoragePool.VirtualDiskName -Volume1Label $config.StoragePool.Volume1Label -Volume2Label $config.StoragePool.Volume2Label
    
    Write-Host ""
    
    # Step 3: Install Windows updates
    Write-Host "Step 3: Installing Windows updates..." -ForegroundColor Yellow
    $results["Windows Updates Installation"] = Install-WindowsUpdates -AutoReboot $config.WindowsUpdates.AutoReboot
    
    Write-Host ""
    
    # Step 4: Install Parsec
    Write-Host "Step 4: Installing Parsec..." -ForegroundColor Yellow
    $results["Parsec Installation"] = Install-Parsec
    
    Write-Host ""
    
    # Display summary
    Write-SetupSummary -Results $results
}
catch {
    Write-Error "Setup failed: $($_.Exception.Message)"
    Write-Host "`nPartial results:" -ForegroundColor Yellow
    Write-SetupSummary -Results $results
    exit 1
}

# Check if reboot is needed
if (Get-WURebootStatus -Silent -ErrorAction SilentlyContinue) {
    Write-Host "`nNOTE: A system reboot is recommended to complete Windows updates." -ForegroundColor Yellow
    Write-Host "You can reboot manually or run: Restart-Computer" -ForegroundColor Yellow
}

Write-Host "`nVM setup script completed successfully!" -ForegroundColor Green
exit 0
# Feature: Windows Updates Installation
# Downloads and installs all available Windows updates

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [hashtable]$Config = @{}
)

# Feature metadata
$FeatureInfo = @{
    Name = "Windows Updates"
    Description = "Downloads and installs all available Windows updates"
    Version = "1.0.0"
    RequiresReboot = $true
    Prerequisites = @("Administrator privileges", "Internet connectivity", "Windows Update service")
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
    
    # Check internet connectivity
    try {
        $null = Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        $issues += "No internet connectivity detected: $($_.Exception.Message)"
    }
    
    # Check Windows Update service
    try {
        $wuService = Get-Service -Name "wuauserv" -ErrorAction Stop
        if ($wuService.Status -ne "Running") {
            $issues += "Windows Update service is not running (Status: $($wuService.Status))"
        }
    }
    catch {
        $issues += "Windows Update service not available: $($_.Exception.Message)"
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
        AutoReboot = $false
        IncludeOptional = $false
        TimeoutMinutes = 60
        MaxRetries = 3
    }
    
    # Merge with provided config
    $featureConfig = $defaultConfig.Clone()
    if ($Config.WindowsUpdates) {
        foreach ($key in $Config.WindowsUpdates.Keys) {
            if ($featureConfig.ContainsKey($key)) {
                $featureConfig[$key] = $Config.WindowsUpdates[$key]
            }
        }
    }
    
    try {
        Write-Host "Installing Windows Updates..." -ForegroundColor Green
        
        # Install PSWindowsUpdate module if not present
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Host "Installing PSWindowsUpdate module..." -ForegroundColor Cyan
            
            # Ensure NuGet provider is available
            $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
            if (-not $nugetProvider -or $nugetProvider.Version -lt [version]"2.8.5.201") {
                Write-Host "Installing NuGet package provider..." -ForegroundColor Cyan
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
            }
            
            # Set PSGallery as trusted if not already
            $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
            if ($psGallery -and $psGallery.InstallationPolicy -ne "Trusted") {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            }
            
            Install-Module -Name PSWindowsUpdate -Force -AllowClobber -Scope AllUsers
        }
        
        Import-Module PSWindowsUpdate -Force
        
        # Get available updates
        Write-Host "Checking for available updates..." -ForegroundColor Cyan
        $updates = Get-WUList -MicrosoftUpdate
        
        if ($featureConfig.IncludeOptional) {
            $optionalUpdates = Get-WUList -Category "Optional"
            if ($optionalUpdates) {
                $updates += $optionalUpdates
            }
        }
        
        if ($updates.Count -eq 0) {
            Write-Host "No updates available." -ForegroundColor Yellow
            return @{
                Success = $true
                Message = "No Windows updates available"
                Data = @{
                    UpdatesInstalled = 0
                    RebootRequired = $false
                }
            }
        }
        
        Write-Host "Found $($updates.Count) updates available:" -ForegroundColor Cyan
        $updates | ForEach-Object {
            Write-Host "  - $($_.Title) ($($_.Size / 1MB | ForEach-Object { '{0:N2}' -f $_ }) MB)" -ForegroundColor Gray
        }
        
        # Install updates with retry logic
        $retryCount = 0
        $installSuccess = $false
        $installResult = $null
        
        do {
            try {
                Write-Host "Installing updates (Attempt $($retryCount + 1)/$($featureConfig.MaxRetries))..." -ForegroundColor Cyan
                
                $installParams = @{
                    MicrosoftUpdate = $true
                    AcceptAll = $true
                    AutoReboot = $featureConfig.AutoReboot
                    Confirm = $false
                    Verbose = $false
                }
                
                $installResult = Install-WindowsUpdate @installParams
                $installSuccess = $true
                break
            }
            catch {
                $retryCount++
                Write-Warning "Update installation failed (Attempt $retryCount): $($_.Exception.Message)"
                
                if ($retryCount -lt $featureConfig.MaxRetries) {
                    Write-Host "Waiting 30 seconds before retry..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 30
                }
            }
        } while ($retryCount -lt $featureConfig.MaxRetries -and -not $installSuccess)
        
        if (-not $installSuccess) {
            throw "Failed to install updates after $($featureConfig.MaxRetries) attempts"
        }
        
        # Check if reboot is required
        $rebootRequired = $false
        try {
            $rebootRequired = Get-WURebootStatus -Silent
        }
        catch {
            # Fallback method to check for pending reboot
            $pendingReboot = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
            ) | Where-Object { Test-Path $_ }
            
            $rebootRequired = $pendingReboot.Count -gt 0
        }
        
        $installedCount = if ($installResult) { $installResult.Count } else { $updates.Count }
        
        Write-Host "Windows updates installation completed!" -ForegroundColor Green
        Write-Host "Updates installed: $installedCount" -ForegroundColor Green
        
        if ($rebootRequired) {
            Write-Warning "A reboot is required to complete the installation."
            if ($featureConfig.AutoReboot) {
                Write-Host "Rebooting in 10 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 10
                Restart-Computer -Force
            }
        }
        
        return @{
            Success = $true
            Message = "Windows updates installed successfully"
            Data = @{
                UpdatesInstalled = $installedCount
                RebootRequired = $rebootRequired
                AutoReboot = $featureConfig.AutoReboot
            }
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to install Windows updates: $($_.Exception.Message)"
            Error = $_
        }
    }
}

# Export feature information and functions
if ($MyInvocation.InvocationName -ne '.') {
    # Script is being executed directly, not dot-sourced
    Write-Host "Windows Updates Feature - $($FeatureInfo.Name)" -ForegroundColor Cyan
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
        if ($result.Data.RebootRequired -and -not $result.Data.AutoReboot) {
            Write-Warning "Reboot required to complete Windows updates installation"
        }
        exit 0
    }
    else {
        Write-Error $result.Message
        exit 1
    }
}

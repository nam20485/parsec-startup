# Feature: Parsec Installation
# Downloads and installs Parsec for remote desktop access

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [hashtable]$Config = @{}
)

# Feature metadata
$FeatureInfo = @{
    Name = "Parsec Installation"
    Description = "Downloads and installs Parsec for remote desktop access"
    Version = "1.0.0"
    RequiresReboot = $false
    Prerequisites = @("Administrator privileges", "Internet connectivity")
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
    
    # Check internet connectivity to Parsec
    try {
        $null = Invoke-WebRequest -Uri "https://builds.parsec.app" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        $issues += "Cannot reach Parsec download server: $($_.Exception.Message)"
    }
    
    # Check if Parsec is already installed
    $existingInstall = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | 
                     Where-Object { $_.DisplayName -like "*Parsec*" }
    
    if ($existingInstall) {
        $issues += "Parsec is already installed (Version: $($existingInstall.DisplayVersion))"
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
        DownloadUrl = "https://builds.parsec.app/package/parsec-windows.exe"
        DownloadPath = ""
        InstallArgs = "/S"
        TimeoutSeconds = 300
        CleanupInstaller = $true
        ValidateInstallation = $true
    }
    
    # Merge with provided config
    $featureConfig = $defaultConfig.Clone()
    if ($Config.Parsec) {
        foreach ($key in $Config.Parsec.Keys) {
            if ($featureConfig.ContainsKey($key)) {
                $featureConfig[$key] = $Config.Parsec[$key]
            }
        }
    }
    
    # Set download path if not specified
    if (-not $featureConfig.DownloadPath) {
        $featureConfig.DownloadPath = "$env:TEMP\parsec-windows.exe"
    }
    
    try {
        Write-Host "Installing Parsec..." -ForegroundColor Green
        
        # Download Parsec installer
        Write-Host "Downloading Parsec installer from: $($featureConfig.DownloadUrl)" -ForegroundColor Cyan
        Write-Host "Download path: $($featureConfig.DownloadPath)" -ForegroundColor Gray
        
        $downloadParams = @{
            Uri = $featureConfig.DownloadUrl
            OutFile = $featureConfig.DownloadPath
            UseBasicParsing = $true
            TimeoutSec = $featureConfig.TimeoutSeconds
        }
        
        # Create download directory if it doesn't exist
        $downloadDir = Split-Path $featureConfig.DownloadPath -Parent
        if (-not (Test-Path $downloadDir)) {
            New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null
        }
        
        Invoke-WebRequest @downloadParams
        
        if (-not (Test-Path $featureConfig.DownloadPath)) {
            throw "Failed to download Parsec installer to $($featureConfig.DownloadPath)"
        }
        
        # Verify download
        $fileInfo = Get-Item $featureConfig.DownloadPath
        Write-Host "Downloaded installer: $($fileInfo.Length / 1MB | ForEach-Object { '{0:N2}' -f $_ }) MB" -ForegroundColor Cyan
        
        # Install Parsec
        Write-Host "Installing Parsec silently..." -ForegroundColor Cyan
        Write-Host "Install arguments: $($featureConfig.InstallArgs)" -ForegroundColor Gray
        
        $processParams = @{
            FilePath = $featureConfig.DownloadPath
            ArgumentList = $featureConfig.InstallArgs
            Wait = $true
            PassThru = $true
            NoNewWindow = $true
        }
        
        $process = Start-Process @processParams
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Parsec installation completed successfully!" -ForegroundColor Green
        }
        else {
            throw "Parsec installation failed with exit code: $($process.ExitCode)"
        }
        
        # Validate installation
        $installationValid = $false
        $parsecVersion = "Unknown"
        
        if ($featureConfig.ValidateInstallation) {
            Write-Host "Validating Parsec installation..." -ForegroundColor Cyan
            
            # Check registry for installation
            $parsecInstall = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | 
                           Where-Object { $_.DisplayName -like "*Parsec*" } | 
                           Select-Object -First 1
            
            if ($parsecInstall) {
                $installationValid = $true
                $parsecVersion = $parsecInstall.DisplayVersion
                Write-Host "Parsec installation validated (Version: $parsecVersion)" -ForegroundColor Green
            }
            else {
                # Fallback: Check for Parsec executable
                $parsecExe = Get-ChildItem -Path "${env:ProgramFiles}*" -Recurse -Name "parsecd.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($parsecExe) {
                    $installationValid = $true
                    Write-Host "Parsec executable found: $parsecExe" -ForegroundColor Green
                }
                else {
                    Write-Warning "Could not validate Parsec installation through registry or file system"
                }
            }
        }
        else {
            $installationValid = $true  # Assume success if validation is disabled
        }
        
        # Clean up installer
        if ($featureConfig.CleanupInstaller -and (Test-Path $featureConfig.DownloadPath)) {
            Write-Host "Cleaning up installer..." -ForegroundColor Cyan
            Remove-Item -Path $featureConfig.DownloadPath -Force -ErrorAction SilentlyContinue
        }
        
        # Check for Parsec service
        $parsecService = Get-Service -Name "ParsecSvc" -ErrorAction SilentlyContinue
        $serviceStatus = if ($parsecService) { $parsecService.Status } else { "Not Found" }
        
        return @{
            Success = $installationValid
            Message = "Parsec installed successfully"
            Data = @{
                Version = $parsecVersion
                ServiceStatus = $serviceStatus
                InstallPath = $parsecInstall.InstallLocation
                DownloadSize = $fileInfo.Length
            }
        }
    }
    catch {
        # Clean up on failure
        if ($featureConfig.CleanupInstaller -and (Test-Path $featureConfig.DownloadPath)) {
            Remove-Item -Path $featureConfig.DownloadPath -Force -ErrorAction SilentlyContinue
        }
        
        return @{
            Success = $false
            Message = "Failed to install Parsec: $($_.Exception.Message)"
            Error = $_
        }
    }
}

function Get-ParsecStatus {
    [CmdletBinding()]
    param()
    
    $status = @{
        Installed = $false
        Version = $null
        ServiceStatus = $null
        InstallPath = $null
    }
    
    # Check registry
    $parsecInstall = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | 
                   Where-Object { $_.DisplayName -like "*Parsec*" } | 
                   Select-Object -First 1
    
    if ($parsecInstall) {
        $status.Installed = $true
        $status.Version = $parsecInstall.DisplayVersion
        $status.InstallPath = $parsecInstall.InstallLocation
    }
    
    # Check service
    $parsecService = Get-Service -Name "ParsecSvc" -ErrorAction SilentlyContinue
    if ($parsecService) {
        $status.ServiceStatus = $parsecService.Status
    }
    
    return $status
}

# Export feature information and functions
if ($MyInvocation.InvocationName -ne '.') {
    # Script is being executed directly, not dot-sourced
    Write-Host "Parsec Installation Feature - $($FeatureInfo.Name)" -ForegroundColor Cyan
    Write-Host "Description: $($FeatureInfo.Description)" -ForegroundColor Gray
    
    # Check current status
    $currentStatus = Get-ParsecStatus
    if ($currentStatus.Installed) {
        Write-Warning "Parsec is already installed (Version: $($currentStatus.Version))"
        Write-Host "Service Status: $($currentStatus.ServiceStatus)" -ForegroundColor Gray
        exit 0
    }
    
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
        Write-Host "Version: $($result.Data.Version)" -ForegroundColor Green
        Write-Host "Service Status: $($result.Data.ServiceStatus)" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Error $result.Message
        exit 1
    }
}

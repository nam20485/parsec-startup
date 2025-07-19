# Feature: .NET SDK 9 Installation
# Downloads and installs the latest .NET SDK 9

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [hashtable]$Config = @{}
)

# Feature metadata
$FeatureInfo = @{
    Name = ".NET SDK 9 Installation"
    Description = "Downloads and installs the latest .NET SDK 9"
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
    
    # Check internet connectivity to Microsoft
    try {
        $null = Invoke-WebRequest -Uri "https://dotnetcli.azureedge.net" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        $issues += "Cannot reach .NET download server: $($_.Exception.Message)"
    }
    
    # Check if .NET SDK 9 is already installed
    try {
        $dotnetInfo = & dotnet --info 2>$null
        if ($dotnetInfo) {
            $sdkVersions = & dotnet --list-sdks 2>$null
            $net9Sdks = $sdkVersions | Where-Object { $_ -like "9.*" }
            
            if ($net9Sdks) {
                $issues += ".NET SDK 9 is already installed: $($net9Sdks -join ', ')"
            }
        }
    }
    catch {
        # dotnet command not found, which is fine - we'll install it
    }
    
    return $issues
}

function Get-DotNetSdk9DownloadInfo {
    [CmdletBinding()]
    param()
    
    try {
        # For .NET SDK 9, we'll use the direct download URL pattern
        # This is more reliable than parsing complex APIs
        $architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
        
        # .NET SDK 9 download URL pattern
        $downloadUrl = "https://dotnetcli.azureedge.net/dotnet/Sdk/9.0.100/dotnet-sdk-9.0.100-win-$architecture.exe"
        $version = "9.0.100"
        
        # Try to verify the URL exists
        try {
            $response = Invoke-WebRequest -Uri $downloadUrl -Method Head -UseBasicParsing -TimeoutSec 10
            if ($response.StatusCode -eq 200) {
                return @{
                    Version = $version
                    DownloadUrl = $downloadUrl
                    Architecture = $architecture
                    FileName = "dotnet-sdk-9.0.100-win-$architecture.exe"
                }
            }
        }
        catch {
            # If specific version doesn't exist, try the latest pattern
            $downloadUrl = "https://dotnetcli.azureedge.net/dotnet/Sdk/release/9.0.1xx/dotnet-sdk-latest-win-$architecture.exe"
            
            return @{
                Version = "Latest 9.0.1xx"
                DownloadUrl = $downloadUrl
                Architecture = $architecture
                FileName = "dotnet-sdk-latest-win-$architecture.exe"
            }
        }
        
        return @{
            Version = $version
            DownloadUrl = $downloadUrl
            Architecture = $architecture
            FileName = "dotnet-sdk-9.0.100-win-$architecture.exe"
        }
    }
    catch {
        throw "Failed to get .NET SDK 9 download information: $($_.Exception.Message)"
    }
}

function Install-Feature {
    [CmdletBinding()]
    param(
        [hashtable]$Config = @{}
    )
    
    # Default configuration
    $defaultConfig = @{
        Version = "Latest"  # or specific version like "9.0.100"
        DownloadPath = ""
        InstallArgs = "/quiet /norestart"
        TimeoutSeconds = 600
        CleanupInstaller = $true
        ValidateInstallation = $true
        AddToPath = $true
    }
    
    # Merge with provided config
    $featureConfig = $defaultConfig.Clone()
    if ($Config.DotNetSDK) {
        foreach ($key in $Config.DotNetSDK.Keys) {
            if ($featureConfig.ContainsKey($key)) {
                $featureConfig[$key] = $Config.DotNetSDK[$key]
            }
        }
    }
    
    try {
        Write-Host "Installing .NET SDK 9..." -ForegroundColor Green
        
        # Get download information
        Write-Host "Getting .NET SDK 9 download information..." -ForegroundColor Cyan
        $downloadInfo = Get-DotNetSdk9DownloadInfo
        
        Write-Host "Found .NET SDK version: $($downloadInfo.Version)" -ForegroundColor Cyan
        Write-Host "Architecture: $($downloadInfo.Architecture)" -ForegroundColor Cyan
        Write-Host "Download URL: $($downloadInfo.DownloadUrl)" -ForegroundColor Gray
        
        # Set download path if not specified
        if (-not $featureConfig.DownloadPath) {
            $featureConfig.DownloadPath = Join-Path $env:TEMP $downloadInfo.FileName
        }
        
        # Download .NET SDK installer
        Write-Host "Downloading .NET SDK 9 installer..." -ForegroundColor Cyan
        Write-Host "Download path: $($featureConfig.DownloadPath)" -ForegroundColor Gray
        
        $downloadParams = @{
            Uri = $downloadInfo.DownloadUrl
            OutFile = $featureConfig.DownloadPath
            UseBasicParsing = $true
            TimeoutSec = $featureConfig.TimeoutSeconds
        }
        
        # Create download directory if it doesn't exist
        $downloadDir = Split-Path $featureConfig.DownloadPath -Parent
        if (-not (Test-Path $downloadDir)) {
            New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null
        }
        
        # Download with progress
        $progressPreference = $ProgressPreference
        $ProgressPreference = 'Continue'
        
        try {
            Invoke-WebRequest @downloadParams
        }
        finally {
            $ProgressPreference = $progressPreference
        }
        
        if (-not (Test-Path $featureConfig.DownloadPath)) {
            throw "Failed to download .NET SDK installer to $($featureConfig.DownloadPath)"
        }
        
        # Verify download
        $fileInfo = Get-Item $featureConfig.DownloadPath
        Write-Host "Downloaded installer: $($fileInfo.Length / 1MB | ForEach-Object { '{0:N2}' -f $_ }) MB" -ForegroundColor Cyan
        
        # Install .NET SDK
        Write-Host "Installing .NET SDK 9..." -ForegroundColor Cyan
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
            Write-Host ".NET SDK 9 installation completed successfully!" -ForegroundColor Green
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Host ".NET SDK 9 installation completed successfully (reboot recommended)!" -ForegroundColor Green
        }
        else {
            throw ".NET SDK 9 installation failed with exit code: $($process.ExitCode)"
        }
        
        # Validate installation
        $installationValid = $false
        $installedVersion = "Unknown"
        $installPath = ""
        
        if ($featureConfig.ValidateInstallation) {
            Write-Host "Validating .NET SDK 9 installation..." -ForegroundColor Cyan
            
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            # Wait a moment for installation to complete
            Start-Sleep -Seconds 5
            
            try {
                # Check if dotnet command is available
                $dotnetInfo = & dotnet --info 2>$null
                if ($dotnetInfo) {
                    Write-Host "✓ dotnet command is available" -ForegroundColor Green
                    
                    # Get installed SDK versions
                    $sdkVersions = & dotnet --list-sdks 2>$null
                    $net9Sdks = $sdkVersions | Where-Object { $_ -like "9.*" }
                    
                    if ($net9Sdks) {
                        $installationValid = $true
                        $installedVersion = ($net9Sdks | Select-Object -First 1) -split '\s+' | Select-Object -First 1
                        
                        # Extract install path
                        $sdkPath = ($net9Sdks | Select-Object -First 1) -replace '.*\[(.*)\].*', '$1'
                        $installPath = Split-Path $sdkPath -Parent
                        
                        Write-Host "✓ .NET SDK 9 installation validated" -ForegroundColor Green
                        Write-Host "  Installed version: $installedVersion" -ForegroundColor Green
                        Write-Host "  Install path: $installPath" -ForegroundColor Green
                    }
                    else {
                        Write-Warning ".NET SDK 9 not found in installed SDKs list"
                        Write-Host "Available SDKs:" -ForegroundColor Gray
                        $sdkVersions | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
                    }
                }
                else {
                    Write-Warning "dotnet command not available after installation"
                }
            }
            catch {
                Write-Warning "Could not validate .NET SDK installation: $($_.Exception.Message)"
                # Try alternative validation
                $dotnetPath = Get-Command dotnet -ErrorAction SilentlyContinue
                if ($dotnetPath) {
                    $installationValid = $true
                    Write-Host "✓ dotnet executable found at: $($dotnetPath.Source)" -ForegroundColor Green
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
        
        # Add to PATH if requested (usually handled by installer, but just in case)
        if ($featureConfig.AddToPath -and $installPath) {
            $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $dotnetPath = Join-Path $installPath "dotnet.exe"
            
            if ((Test-Path $dotnetPath) -and ($currentPath -notlike "*$installPath*")) {
                Write-Host "Adding .NET to system PATH..." -ForegroundColor Cyan
                $newPath = "$currentPath;$installPath"
                [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
            }
        }
        
        return @{
            Success = $installationValid
            Message = ".NET SDK 9 installed successfully"
            Data = @{
                Version = $installedVersion
                InstallPath = $installPath
                Architecture = $downloadInfo.Architecture
                DownloadSize = $fileInfo.Length
                RequiresReboot = $process.ExitCode -eq 3010
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
            Message = "Failed to install .NET SDK 9: $($_.Exception.Message)"
            Error = $_
        }
    }
}

function Get-DotNetSdkStatus {
    [CmdletBinding()]
    param()
    
    $status = @{
        DotNetInstalled = $false
        Sdk9Installed = $false
        InstalledSdks = @()
        DotNetVersion = $null
        InstallPath = $null
    }
    
    try {
        # Check if dotnet command is available
        $dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
        if ($dotnetCommand) {
            $status.DotNetInstalled = $true
            $status.InstallPath = Split-Path $dotnetCommand.Source -Parent
            
            # Get .NET version
            $versionOutput = & dotnet --version 2>$null
            if ($versionOutput) {
                $status.DotNetVersion = $versionOutput.Trim()
            }
            
            # Get installed SDKs
            $sdkOutput = & dotnet --list-sdks 2>$null
            if ($sdkOutput) {
                $status.InstalledSdks = $sdkOutput
                $net9Sdks = $sdkOutput | Where-Object { $_ -like "9.*" }
                $status.Sdk9Installed = $net9Sdks.Count -gt 0
            }
        }
    }
    catch {
        # dotnet not available
    }
    
    return $status
}

# Export feature information and functions
if ($MyInvocation.InvocationName -ne '.') {
    # Script is being executed directly, not dot-sourced
    Write-Host ".NET SDK 9 Installation Feature - $($FeatureInfo.Name)" -ForegroundColor Cyan
    Write-Host "Description: $($FeatureInfo.Description)" -ForegroundColor Gray
    
    # Check current status
    $currentStatus = Get-DotNetSdkStatus
    if ($currentStatus.Sdk9Installed) {
        Write-Warning ".NET SDK 9 is already installed"
        Write-Host "Installed SDKs:" -ForegroundColor Gray
        $currentStatus.InstalledSdks | Where-Object { $_ -like "9.*" } | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Gray
        }
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
        Write-Host "Install Path: $($result.Data.InstallPath)" -ForegroundColor Green
        if ($result.Data.RequiresReboot) {
            Write-Warning "A system reboot is recommended to complete the installation"
        }
        exit 0
    }
    else {
        Write-Error $result.Message
        exit 1
    }
}

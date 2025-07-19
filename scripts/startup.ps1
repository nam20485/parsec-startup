# VM Post-Initialization Startup Script - Modular Edition
# This script automatically discovers and executes feature scripts from the features directory
# Features are executed in alphabetical order based on filename

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ConfigFile = "",
    [string[]]$IncludeFeatures = @(),
    [string[]]$ExcludeFeatures = @(),
    [switch]$ListFeatures,
    [switch]$DryRun,
    [switch]$ContinueOnError = $true
)

# Script configuration
$scriptConfig = @{
    FeaturesDirectory = Join-Path $PSScriptRoot "features"
    DefaultConfigFile = Join-Path $PSScriptRoot "Config.psd1"
    LogFile = ""
    ShowTimestamps = $true
}

function Write-LogMessage {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$Level = "Info",
        [ConsoleColor]$ForegroundColor = "White"
    )
    
    $timestamp = if ($scriptConfig.ShowTimestamps) { "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] " } else { "" }
    $logMessage = "$timestamp$Level`: $Message"
    
    # Write to console
    Write-Host $logMessage -ForegroundColor $ForegroundColor
    
    # Write to log file if specified
    if ($scriptConfig.LogFile -and (Test-Path (Split-Path $scriptConfig.LogFile -Parent))) {
        Add-Content -Path $scriptConfig.LogFile -Value $logMessage
    }
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()
    
    $issues = @()
    
    # Check if running as administrator
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $issues += "Script must be run as Administrator"
    }
    
    # Check features directory exists
    if (-not (Test-Path $scriptConfig.FeaturesDirectory)) {
        $issues += "Features directory not found: $($scriptConfig.FeaturesDirectory)"
    }
    
    # Check for PowerShell execution policy
    $executionPolicy = Get-ExecutionPolicy
    if ($executionPolicy -eq "Restricted") {
        $issues += "PowerShell execution policy is Restricted. Set to RemoteSigned or Unrestricted."
    }
    
    return $issues
}

function Get-FeatureScripts {
    [CmdletBinding()]
    param()
    
    if (-not (Test-Path $scriptConfig.FeaturesDirectory)) {
        Write-LogMessage "Features directory not found: $($scriptConfig.FeaturesDirectory)" -Level "Warning" -ForegroundColor Yellow
        return @()
    }
    
    # Get all PowerShell scripts in features directory
    $featureFiles = Get-ChildItem -Path $scriptConfig.FeaturesDirectory -Filter "*.ps1" | Sort-Object Name
    
    $features = @()
    foreach ($file in $featureFiles) {
        try {
            # Read the script to extract metadata
            $scriptContent = Get-Content -Path $file.FullName -Raw
            
            # Extract FeatureInfo if present
            $featureInfo = $null
            if ($scriptContent -match '\$FeatureInfo\s*=\s*@{([^}]+)}') {
                try {
                    # This is a simplified extraction - in practice, you might want more robust parsing
                    $featureInfoText = $Matches[1]
                    $featureInfo = @{
                        Name = "Unknown"
                        Description = "No description available"
                        Version = "1.0.0"
                        RequiresReboot = $false
                        Prerequisites = @()
                    }
                    
                    # Extract name
                    if ($featureInfoText -match 'Name\s*=\s*"([^"]+)"') {
                        $featureInfo.Name = $Matches[1]
                    }
                    
                    # Extract description
                    if ($featureInfoText -match 'Description\s*=\s*"([^"]+)"') {
                        $featureInfo.Description = $Matches[1]
                    }
                    
                    # Extract version
                    if ($featureInfoText -match 'Version\s*=\s*"([^"]+)"') {
                        $featureInfo.Version = $Matches[1]
                    }
                    
                    # Extract reboot requirement
                    if ($featureInfoText -match 'RequiresReboot\s*=\s*\$(\w+)') {
                        $featureInfo.RequiresReboot = $Matches[1] -eq "true"
                    }
                }
                catch {
                    Write-LogMessage "Warning: Could not parse FeatureInfo for $($file.Name): $($_.Exception.Message)" -Level "Warning" -ForegroundColor Yellow
                }
            }
            
            # Fallback to filename-based info
            if (-not $featureInfo) {
                $featureInfo = @{
                    Name = $file.BaseName
                    Description = "Feature script: $($file.Name)"
                    Version = "1.0.0"
                    RequiresReboot = $false
                    Prerequisites = @()
                }
            }
            
            $features += [PSCustomObject]@{
                FileName = $file.Name
                FullPath = $file.FullName
                Name = $featureInfo.Name
                Description = $featureInfo.Description
                Version = $featureInfo.Version
                RequiresReboot = $featureInfo.RequiresReboot
                Prerequisites = $featureInfo.Prerequisites
                Enabled = $true
            }
        }
        catch {
            Write-LogMessage "Error processing feature file $($file.Name): $($_.Exception.Message)" -Level "Error" -ForegroundColor Red
        }
    }
    
    return $features
}

function Invoke-FeatureScript {
    [CmdletBinding()]
    param(
        [PSCustomObject]$Feature,
        [hashtable]$Config = @{}
    )
    
    try {
        Write-LogMessage "Executing feature: $($Feature.Name)" -Level "Info" -ForegroundColor Cyan
        Write-LogMessage "Description: $($Feature.Description)" -Level "Info" -ForegroundColor Gray
        Write-LogMessage "Script: $($Feature.FileName)" -Level "Info" -ForegroundColor Gray
        
        if ($DryRun) {
            Write-LogMessage "DRY RUN: Would execute $($Feature.FileName)" -Level "Info" -ForegroundColor Yellow
            return @{
                Success = $true
                Message = "Dry run - not executed"
                Data = @{}
                DryRun = $true
            }
        }
        
        # Dot-source the feature script to load its functions
        . $Feature.FullPath
        
        # Check if required functions exist
        if (-not (Get-Command "Test-FeaturePrerequisites" -ErrorAction SilentlyContinue)) {
            throw "Feature script missing Test-FeaturePrerequisites function"
        }
        
        if (-not (Get-Command "Install-Feature" -ErrorAction SilentlyContinue)) {
            throw "Feature script missing Install-Feature function"
        }
        
        # Test prerequisites
        Write-LogMessage "Checking prerequisites for $($Feature.Name)..." -Level "Info" -ForegroundColor Cyan
        $prereqIssues = Test-FeaturePrerequisites
        
        if ($prereqIssues.Count -gt 0) {
            $issueList = $prereqIssues -join "; "
            throw "Prerequisites not met: $issueList"
        }
        
        Write-LogMessage "Prerequisites check passed" -Level "Info" -ForegroundColor Green
        
        # Execute feature installation
        Write-LogMessage "Installing feature: $($Feature.Name)" -Level "Info" -ForegroundColor Cyan
        $result = Install-Feature -Config $Config
        
        if ($result.Success) {
            Write-LogMessage "Feature '$($Feature.Name)' completed successfully: $($result.Message)" -Level "Success" -ForegroundColor Green
        }
        else {
            throw $result.Message
        }
        
        return $result
    }
    catch {
        $errorMsg = "Feature '$($Feature.Name)' failed: $($_.Exception.Message)"
        Write-LogMessage $errorMsg -Level "Error" -ForegroundColor Red
        
        return @{
            Success = $false
            Message = $errorMsg
            Error = $_
        }
    }
}

function Write-StartupSummary {
    [CmdletBinding()]
    param(
        [hashtable]$Results,
        [PSCustomObject[]]$Features
    )
    
    Write-LogMessage "" -Level "Info"
    Write-LogMessage ("=" * 60) -Level "Info" -ForegroundColor Cyan
    Write-LogMessage "VM Startup Summary" -Level "Info" -ForegroundColor Cyan
    Write-LogMessage ("=" * 60) -Level "Info" -ForegroundColor Cyan
    
    $successCount = 0
    $failureCount = 0
    $skippedCount = 0
    $rebootRequired = $false
    
    foreach ($feature in $Features) {
        if ($Results.ContainsKey($feature.FileName)) {
            $result = $Results[$feature.FileName]
            
            if ($result.DryRun) {
                $status = "DRY RUN"
                $color = "Yellow"
                $skippedCount++
            }
            elseif ($result.Success) {
                $status = "✓ SUCCESS"
                $color = "Green"
                $successCount++
                
                if ($feature.RequiresReboot -or ($result.Data -and $result.Data.RebootRequired)) {
                    $rebootRequired = $true
                }
            }
            else {
                $status = "✗ FAILED"
                $color = "Red"
                $failureCount++
            }
            
            Write-LogMessage "$($feature.Name): $status" -Level "Info" -ForegroundColor $color
            if ($result.Message -and $result.Message -ne $status) {
                Write-LogMessage "  $($result.Message)" -Level "Info" -ForegroundColor Gray
            }
        }
        else {
            Write-LogMessage "$($feature.Name): SKIPPED" -Level "Info" -ForegroundColor Yellow
            $skippedCount++
        }
    }
    
    Write-LogMessage "" -Level "Info"
    Write-LogMessage "Summary: $successCount succeeded, $failureCount failed, $skippedCount skipped" -Level "Info" -ForegroundColor Cyan
    Write-LogMessage "Completed at: $(Get-Date)" -Level "Info" -ForegroundColor Cyan
    
    if ($rebootRequired) {
        Write-LogMessage "" -Level "Info"
        Write-LogMessage "⚠ A system reboot is required to complete the installation." -Level "Warning" -ForegroundColor Yellow
        Write-LogMessage "Run 'Restart-Computer' to reboot the system." -Level "Info" -ForegroundColor Yellow
    }
    
    if ($failureCount -gt 0) {
        Write-LogMessage "" -Level "Info"
        Write-LogMessage "Some features failed to install. Review the errors above." -Level "Warning" -ForegroundColor Yellow
        return $false
    }
    
    Write-LogMessage "" -Level "Info"
    Write-LogMessage "All features completed successfully!" -Level "Success" -ForegroundColor Green
    return $true
}

# Main execution
try {
    Write-LogMessage "VM Post-Initialization Startup Script (Modular Edition)" -Level "Info" -ForegroundColor Cyan
    Write-LogMessage "Timestamp: $(Get-Date)" -Level "Info" -ForegroundColor Gray
    Write-LogMessage "" -Level "Info"
    
    # Load configuration
    $config = @{}
    $configPath = if ($ConfigFile) { $ConfigFile } else { $scriptConfig.DefaultConfigFile }
    
    if ($configPath -and (Test-Path $configPath)) {
        try {
            $config = Import-PowerShellDataFile -Path $configPath
            Write-LogMessage "Configuration loaded from: $configPath" -Level "Info" -ForegroundColor Green
        }
        catch {
            Write-LogMessage "Warning: Could not load configuration from $configPath`: $($_.Exception.Message)" -Level "Warning" -ForegroundColor Yellow
        }
    }
    else {
        Write-LogMessage "No configuration file found, using defaults" -Level "Info" -ForegroundColor Yellow
    }
    
    # Update script config from loaded config
    if ($config.Logging -and $config.Logging.LogFile) {
        $scriptConfig.LogFile = $config.Logging.LogFile
    }
    if ($config.Logging -and $config.Logging.ContainsKey('ShowTimestamps')) {
        $scriptConfig.ShowTimestamps = $config.Logging.ShowTimestamps
    }
    
    # Check prerequisites
    Write-LogMessage "Checking prerequisites..." -Level "Info" -ForegroundColor Yellow
    $prereqIssues = Test-Prerequisites
    if ($prereqIssues.Count -gt 0) {
        Write-LogMessage "Prerequisites check failed:" -Level "Error" -ForegroundColor Red
        $prereqIssues | ForEach-Object { Write-LogMessage "- $_" -Level "Error" -ForegroundColor Red }
        exit 1
    }
    Write-LogMessage "Prerequisites check passed" -Level "Info" -ForegroundColor Green
    Write-LogMessage "" -Level "Info"
    
    # Discover features
    Write-LogMessage "Discovering feature scripts..." -Level "Info" -ForegroundColor Yellow
    $allFeatures = Get-FeatureScripts
    
    if ($allFeatures.Count -eq 0) {
        Write-LogMessage "No feature scripts found in: $($scriptConfig.FeaturesDirectory)" -Level "Warning" -ForegroundColor Yellow
        exit 0
    }
    
    # Filter features based on include/exclude parameters
    $features = $allFeatures
    
    if ($IncludeFeatures.Count -gt 0) {
        $features = $features | Where-Object { $_.FileName -in $IncludeFeatures -or $_.Name -in $IncludeFeatures }
    }
    
    if ($ExcludeFeatures.Count -gt 0) {
        $features = $features | Where-Object { $_.FileName -notin $ExcludeFeatures -and $_.Name -notin $ExcludeFeatures }
    }
    
    Write-LogMessage "Found $($allFeatures.Count) feature(s), $($features.Count) selected for execution:" -Level "Info" -ForegroundColor Cyan
    $features | ForEach-Object {
        $status = if ($DryRun) { " [DRY RUN]" } else { "" }
        Write-LogMessage "  - $($_.Name) ($($_.FileName))$status" -Level "Info" -ForegroundColor Gray
    }
    
    # List features and exit if requested
    if ($ListFeatures) {
        Write-LogMessage "" -Level "Info"
        Write-LogMessage "Available Features:" -Level "Info" -ForegroundColor Cyan
        $allFeatures | ForEach-Object {
            Write-LogMessage "  $($_.FileName)" -Level "Info" -ForegroundColor White
            Write-LogMessage "    Name: $($_.Name)" -Level "Info" -ForegroundColor Gray
            Write-LogMessage "    Description: $($_.Description)" -Level "Info" -ForegroundColor Gray
            Write-LogMessage "    Version: $($_.Version)" -Level "Info" -ForegroundColor Gray
            Write-LogMessage "    Requires Reboot: $($_.RequiresReboot)" -Level "Info" -ForegroundColor Gray
            Write-LogMessage "" -Level "Info"
        }
        exit 0
    }
    
    if ($features.Count -eq 0) {
        Write-LogMessage "No features selected for execution" -Level "Warning" -ForegroundColor Yellow
        exit 0
    }
    
    Write-LogMessage "" -Level "Info"
    
    # Execute features
    $results = @{}
    $overallSuccess = $true
    
    foreach ($feature in $features) {
        try {
            $result = Invoke-FeatureScript -Feature $feature -Config $config
            $results[$feature.FileName] = $result
            
            if (-not $result.Success -and -not $ContinueOnError) {
                Write-LogMessage "Stopping execution due to failure in '$($feature.Name)'" -Level "Error" -ForegroundColor Red
                $overallSuccess = $false
                break
            }
            
            if (-not $result.Success) {
                $overallSuccess = $false
            }
        }
        catch {
            $errorMsg = "Unexpected error executing '$($feature.Name)': $($_.Exception.Message)"
            Write-LogMessage $errorMsg -Level "Error" -ForegroundColor Red
            
            $results[$feature.FileName] = @{
                Success = $false
                Message = $errorMsg
                Error = $_
            }
            
            $overallSuccess = $false
            
            if (-not $ContinueOnError) {
                break
            }
        }
        
        Write-LogMessage "" -Level "Info"
    }
    
    # Display summary
    $summarySuccess = Write-StartupSummary -Results $results -Features $features
    
    if ($overallSuccess -and $summarySuccess) {
        Write-LogMessage "VM startup script completed successfully!" -Level "Success" -ForegroundColor Green
        exit 0
    }
    else {
        Write-LogMessage "VM startup script completed with errors." -Level "Error" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-LogMessage "Fatal error in startup script: $($_.Exception.Message)" -Level "Error" -ForegroundColor Red
    Write-LogMessage $_.ScriptStackTrace -Level "Error" -ForegroundColor Red
    exit 1
}
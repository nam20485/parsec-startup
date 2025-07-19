# Test script for Modular VM Setup Framework
# This script validates the modular setup environment and feature prerequisites

#Requires -RunAsAdministrator

param(
    [switch]$DryRun,
    [string]$FeaturesDirectory = ""
)

# Default to dry run mode
if (-not $PSBoundParameters.ContainsKey('DryRun')) {
    $DryRun = $true
}

# Set features directory
if (-not $FeaturesDirectory) {
    $FeaturesDirectory = Join-Path $PSScriptRoot "features"
}

Write-Host "VM Setup Framework Test Script" -ForegroundColor Cyan
Write-Host "Dry Run Mode: $DryRun" -ForegroundColor Yellow
Write-Host "Features Directory: $FeaturesDirectory" -ForegroundColor Gray
Write-Host ""

# Test 1: Framework prerequisites
Write-Host "Testing Framework Prerequisites..." -ForegroundColor Green
$frameworkIssues = @()

# Check if running as administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $frameworkIssues += "Must be run as Administrator"
}

# Check features directory exists
if (-not (Test-Path $FeaturesDirectory)) {
    $frameworkIssues += "Features directory not found: $FeaturesDirectory"
}

# Check PowerShell execution policy
$executionPolicy = Get-ExecutionPolicy
if ($executionPolicy -eq "Restricted") {
    $frameworkIssues += "PowerShell execution policy is Restricted"
}

if ($frameworkIssues.Count -eq 0) {
    Write-Host "✓ Framework prerequisites check passed" -ForegroundColor Green
}
else {
    Write-Host "✗ Framework prerequisites check failed:" -ForegroundColor Red
    $frameworkIssues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}
Write-Host ""

# Test 2: Discover and validate feature scripts
Write-Host "Discovering Feature Scripts..." -ForegroundColor Green

if (-not (Test-Path $FeaturesDirectory)) {
    Write-Host "✗ Cannot test features - directory not found" -ForegroundColor Red
    exit 1
}

$featureFiles = Get-ChildItem -Path $FeaturesDirectory -Filter "*.ps1" | Sort-Object Name

if ($featureFiles.Count -eq 0) {
    Write-Host "⚠ No feature scripts found in $FeaturesDirectory" -ForegroundColor Yellow
}
else {
    Write-Host "Found $($featureFiles.Count) feature script(s):" -ForegroundColor Cyan
    $featureFiles | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor Gray
    }
}
Write-Host ""

# Test 3: Validate each feature script
$featureResults = @{}

foreach ($featureFile in $featureFiles) {
    Write-Host "Testing Feature: $($featureFile.Name)" -ForegroundColor Yellow
    $featureResult = @{
        Name = $featureFile.Name
        Valid = $false
        Issues = @()
        FeatureInfo = $null
    }
    
    try {
        # Check script syntax
        $scriptContent = Get-Content -Path $featureFile.FullName -Raw
        
        # Basic syntax check
        try {
            $null = [System.Management.Automation.PSParser]::Tokenize($scriptContent, [ref]$null)
            Write-Host "  ✓ Script syntax is valid" -ForegroundColor Green
        }
        catch {
            $featureResult.Issues += "Script syntax error: $($_.Exception.Message)"
            Write-Host "  ✗ Script syntax error" -ForegroundColor Red
        }
        
        # Check for required functions
        $requiredFunctions = @("Test-FeaturePrerequisites", "Install-Feature")
        foreach ($func in $requiredFunctions) {
            if ($scriptContent -match "function\s+$func") {
                Write-Host "  ✓ Function $func found" -ForegroundColor Green
            }
            else {
                $featureResult.Issues += "Missing required function: $func"
                Write-Host "  ✗ Missing function: $func" -ForegroundColor Red
            }
        }
        
        # Check for FeatureInfo
        if ($scriptContent -match '\$FeatureInfo\s*=\s*@{') {
            Write-Host "  ✓ FeatureInfo metadata found" -ForegroundColor Green
            
            # Try to extract feature info
            try {
                if ($scriptContent -match 'Name\s*=\s*"([^"]+)"') {
                    $featureName = $Matches[1]
                    Write-Host "    Name: $featureName" -ForegroundColor Gray
                }
                if ($scriptContent -match 'Description\s*=\s*"([^"]+)"') {
                    $featureDescription = $Matches[1]
                    Write-Host "    Description: $featureDescription" -ForegroundColor Gray
                }
                if ($scriptContent -match 'Version\s*=\s*"([^"]+)"') {
                    $featureVersion = $Matches[1]
                    Write-Host "    Version: $featureVersion" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "  ⚠ Could not parse FeatureInfo details" -ForegroundColor Yellow
            }
        }
        else {
            $featureResult.Issues += "Missing FeatureInfo metadata"
            Write-Host "  ⚠ FeatureInfo metadata not found" -ForegroundColor Yellow
        }
        
        # If no syntax errors and has required functions, try to load and test prerequisites
        if ($featureResult.Issues.Count -eq 0 -or ($featureResult.Issues | Where-Object { $_ -like "*syntax*" }).Count -eq 0) {
            try {
                # Dot-source the script to load functions
                . $featureFile.FullName
                
                # Test if functions are callable
                if (Get-Command "Test-FeaturePrerequisites" -ErrorAction SilentlyContinue) {
                    Write-Host "  ✓ Test-FeaturePrerequisites function loaded" -ForegroundColor Green
                    
                    # Call the prerequisite test
                    $prereqIssues = Test-FeaturePrerequisites
                    
                    if ($prereqIssues.Count -eq 0) {
                        Write-Host "  ✓ Feature prerequisites check passed" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  ⚠ Feature prerequisites check failed:" -ForegroundColor Yellow
                        $prereqIssues | ForEach-Object {
                            Write-Host "    - $_" -ForegroundColor Yellow
                        }
                    }
                }
                
                if (Get-Command "Install-Feature" -ErrorAction SilentlyContinue) {
                    Write-Host "  ✓ Install-Feature function loaded" -ForegroundColor Green
                }
                
                $featureResult.Valid = $true
            }
            catch {
                $featureResult.Issues += "Error loading feature script: $($_.Exception.Message)"
                Write-Host "  ✗ Error loading feature script: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    catch {
        $featureResult.Issues += "Error reading feature script: $($_.Exception.Message)"
        Write-Host "  ✗ Error reading feature script" -ForegroundColor Red
    }
    
    $featureResults[$featureFile.Name] = $featureResult
    Write-Host ""
}

# Test 4: Test main startup script
Write-Host "Testing Main Startup Script..." -ForegroundColor Green
$startupScript = Join-Path $PSScriptRoot "startup.ps1"

if (Test-Path $startupScript) {
    Write-Host "✓ startup.ps1 found" -ForegroundColor Green
    
    # Test dry run execution
    try {
        Write-Host "Testing dry run execution..." -ForegroundColor Cyan
        & $startupScript -DryRun -ListFeatures | Out-Null
        Write-Host "✓ Dry run test passed" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Dry run test failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "✗ startup.ps1 not found" -ForegroundColor Red
}
Write-Host ""

# Test 5: Configuration file
Write-Host "Testing Configuration..." -ForegroundColor Green
$configFile = Join-Path $PSScriptRoot "Config.psd1"

if (Test-Path $configFile) {
    Write-Host "✓ Config.psd1 found" -ForegroundColor Green
    
    try {
        $config = Import-PowerShellDataFile -Path $configFile
        Write-Host "✓ Configuration file loaded successfully" -ForegroundColor Green
        
        # Check for expected sections
        $expectedSections = @("Storage", "WindowsUpdates", "Parsec", "Logging", "General")
        foreach ($section in $expectedSections) {
            if ($config.ContainsKey($section)) {
                Write-Host "  ✓ $section section found" -ForegroundColor Green
            }
            else {
                Write-Host "  ⚠ $section section missing" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "✗ Error loading configuration: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "⚠ Config.psd1 not found (will use defaults)" -ForegroundColor Yellow
}
Write-Host ""

# Test 6: System compatibility tests
Write-Host "Testing System Compatibility..." -ForegroundColor Green

# Test internet connectivity
try {
    $null = Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing -TimeoutSec 5
    Write-Host "✓ Internet connectivity available" -ForegroundColor Green
}
catch {
    Write-Host "✗ No internet connectivity: $($_.Exception.Message)" -ForegroundColor Red
}

# Test Storage Spaces (if available)
try {
    $null = Get-StorageSubSystem -ErrorAction Stop
    Write-Host "✓ Storage Spaces available" -ForegroundColor Green
    
    $physicalDisks = Get-PhysicalDisk | Where-Object { $_.CanPool -eq $true }
    Write-Host "  Available disks for pooling: $($physicalDisks.Count)" -ForegroundColor Gray
    
    if ($physicalDisks.Count -ge 2) {
        Write-Host "  ✓ Sufficient disks for striping" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Insufficient disks for striping (need at least 2)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "✗ Storage Spaces not available: $($_.Exception.Message)" -ForegroundColor Red
}

# Test Windows Update service
try {
    $wuService = Get-Service -Name "wuauserv" -ErrorAction Stop
    Write-Host "✓ Windows Update service available (Status: $($wuService.Status))" -ForegroundColor Green
}
catch {
    Write-Host "✗ Windows Update service not available: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Final Summary
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

$validFeatures = ($featureResults.Values | Where-Object { $_.Valid }).Count
$totalFeatures = $featureResults.Count

Write-Host "Framework Prerequisites: $(if ($frameworkIssues.Count -eq 0) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($frameworkIssues.Count -eq 0) { 'Green' } else { 'Red' })
Write-Host "Feature Scripts: $validFeatures/$totalFeatures valid" -ForegroundColor $(if ($validFeatures -eq $totalFeatures) { 'Green' } else { 'Yellow' })
Write-Host "Configuration: $(if (Test-Path $configFile) { 'FOUND' } else { 'MISSING' })" -ForegroundColor $(if (Test-Path $configFile) { 'Green' } else { 'Yellow' })

Write-Host ""

if ($frameworkIssues.Count -eq 0 -and $validFeatures -eq $totalFeatures) {
    Write-Host "✓ All tests passed! Framework is ready for use." -ForegroundColor Green
    Write-Host ""
    Write-Host "To run the setup:" -ForegroundColor Cyan
    Write-Host "  .\startup.ps1                    # Run all features" -ForegroundColor Gray
    Write-Host "  .\startup.ps1 -DryRun            # Test run without changes" -ForegroundColor Gray
    Write-Host "  .\startup.ps1 -ListFeatures      # Show available features" -ForegroundColor Gray
}
else {
    Write-Host "⚠ Some tests failed. Review the issues above before running the setup." -ForegroundColor Yellow
    
    if ($frameworkIssues.Count -gt 0) {
        Write-Host ""
        Write-Host "Framework Issues to Resolve:" -ForegroundColor Red
        $frameworkIssues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }
    
    $invalidFeatures = $featureResults.Values | Where-Object { -not $_.Valid }
    if ($invalidFeatures.Count -gt 0) {
        Write-Host ""
        Write-Host "Feature Issues to Resolve:" -ForegroundColor Red
        foreach ($feature in $invalidFeatures) {
            Write-Host "  $($feature.Name):" -ForegroundColor Red
            $feature.Issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
        }
    }
}

Write-Host ""
Write-Host "Test completed at: $(Get-Date)" -ForegroundColor Gray

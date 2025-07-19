# Test script for VMSetupModule
# This script tests the individual functions without actually executing them

#Requires -RunAsAdministrator

param(
    [switch]$DryRun
)

# Default to dry run mode
if (-not $PSBoundParameters.ContainsKey('DryRun')) {
    $DryRun = $true
}

# Import the module
$moduleDir = $PSScriptRoot
Import-Module "$moduleDir\VMSetupModule.psm1" -Force

Write-Host "VM Setup Module Test Script" -ForegroundColor Cyan
Write-Host "Dry Run Mode: $DryRun" -ForegroundColor Yellow
Write-Host ""

# Test 1: Prerequisites check
Write-Host "Testing Prerequisites Check..." -ForegroundColor Green
try {
    $prereqResult = Test-Prerequisites
    Write-Host "Prerequisites check: $(if ($prereqResult) { 'PASSED' } else { 'FAILED' })" -ForegroundColor $(if ($prereqResult) { 'Green' } else { 'Red' })
}
catch {
    Write-Host "Prerequisites check failed with error: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 2: Check available physical disks
Write-Host "Checking available physical disks for striping..." -ForegroundColor Green
try {
    $physicalDisks = Get-PhysicalDisk | Where-Object { $_.CanPool -eq $true }
    Write-Host "Available disks for pooling: $($physicalDisks.Count)" -ForegroundColor Cyan
    
    if ($physicalDisks.Count -ge 2) {
        Write-Host "✓ Sufficient disks available for striping" -ForegroundColor Green
        $physicalDisks | ForEach-Object {
            Write-Host "  - $($_.FriendlyName) ($($_.Size / 1GB)GB)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "✗ Insufficient disks for striping (need at least 2)" -ForegroundColor Red
    }
}
catch {
    Write-Host "Error checking physical disks: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 3: Check internet connectivity
Write-Host "Testing internet connectivity..." -ForegroundColor Green
try {
    $connectivityTest = Invoke-WebRequest -Uri "https://builds.parsec.app/package/parsec-windows.exe" -Method Head -UseBasicParsing -TimeoutSec 10
    Write-Host "✓ Can reach Parsec download URL" -ForegroundColor Green
    Write-Host "  Response: $($connectivityTest.StatusCode) $($connectivityTest.StatusDescription)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Cannot reach Parsec download URL: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 4: Check Windows Update module availability
Write-Host "Checking PSWindowsUpdate module..." -ForegroundColor Green
$psWindowsUpdate = Get-Module -ListAvailable -Name PSWindowsUpdate
if ($psWindowsUpdate) {
    Write-Host "✓ PSWindowsUpdate module is available (version $($psWindowsUpdate.Version))" -ForegroundColor Green
}
else {
    Write-Host "⚠ PSWindowsUpdate module not installed (will be installed during setup)" -ForegroundColor Yellow
}
Write-Host ""

# Test 5: Check Storage Spaces availability
Write-Host "Testing Storage Spaces availability..." -ForegroundColor Green
try {
    $storageSubsystem = Get-StorageSubSystem
    Write-Host "✓ Storage Spaces available" -ForegroundColor Green
    Write-Host "  Storage Subsystem: $($storageSubsystem.FriendlyName)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Storage Spaces not available: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 6: Function availability
Write-Host "Testing module function availability..." -ForegroundColor Green
$functions = @(
    'Test-Prerequisites',
    'New-StripedVirtualDisk',
    'Install-WindowsUpdates', 
    'Install-Parsec',
    'Write-SetupSummary'
)

foreach ($func in $functions) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-Host "✓ $func is available" -ForegroundColor Green
    }
    else {
        Write-Host "✗ $func is not available" -ForegroundColor Red
    }
}
Write-Host ""

# Configuration test
Write-Host "Testing configuration file..." -ForegroundColor Green
$configPath = "$PSScriptRoot\Config.psd1"
if (Test-Path $configPath) {
    try {
        $config = Import-PowerShellDataFile -Path $configPath
        Write-Host "✓ Configuration file loaded successfully" -ForegroundColor Green
        Write-Host "  Storage Pool Name: $($config.Storage.PoolName)" -ForegroundColor Gray
        Write-Host "  Auto Reboot: $($config.WindowsUpdates.AutoReboot)" -ForegroundColor Gray
    }
    catch {
        Write-Host "✗ Error loading configuration: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "⚠ Configuration file not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Test completed!" -ForegroundColor Cyan
Write-Host "Review the results above before running the actual setup script." -ForegroundColor Yellow

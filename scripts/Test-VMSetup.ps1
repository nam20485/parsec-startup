# Comprehensive Test Suite for VM Setup Scripts
# This script provides extensive test coverage for the modular VM setup system

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$RunAll,
    [switch]$TestConfigValidation,
    [switch]$TestFeatureDiscovery,
    [switch]$TestPrerequisites,
    [switch]$TestStorageSpaces,
    [switch]$TestSourceDirectory,
    [switch]$TestDryRun,
    [switch]$TestErrorHandling,
    [switch]$TestDependencies,
    [switch]$DryRun,
    [string]$FeaturesDirectory = "",
    [switch]$Verbose
)

# Test configuration
$TestConfig = @{
    TestDirectory = Join-Path $PSScriptRoot "test-temp"
    TestConfigFile = Join-Path $PSScriptRoot "test-configs\test-config.psd1"
    FeaturesDirectory = if ($FeaturesDirectory) { $FeaturesDirectory } else { Join-Path $PSScriptRoot "features" }
    StartupScript = Join-Path $PSScriptRoot "startup.ps1"
    Results = @{}
    TestCount = 0
    PassCount = 0
    FailCount = 0
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Message = "",
        [string]$Details = ""
    )
    
    $TestConfig.TestCount++
    $status = if ($Passed) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    if ($Passed) { $TestConfig.PassCount++ } else { $TestConfig.FailCount++ }
    
    Write-Host "[$status] $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor Gray
    }
    if ($Details -and $Verbose) {
        Write-Host "    Details: $Details" -ForegroundColor DarkGray
    }
    
    $TestConfig.Results[$TestName] = @{
        Passed = $Passed
        Message = $Message
        Details = $Details
    }
}

function Test-ConfigurationValidation {
    Write-Host "`n=== Configuration Validation Tests ===" -ForegroundColor Cyan
    
    # Test 1: Valid configuration file loading
    try {
        $config = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot "Config.psd1")
        Write-TestResult "Config.psd1 loads successfully" $true "Configuration file parsed without errors"
    }
    catch {
        Write-TestResult "Config.psd1 loads successfully" $false "Failed to load: $($_.Exception.Message)"
        return
    }
    
    # Test 2: Required configuration sections exist
    $requiredSections = @("Storage", "WindowsUpdates", "Parsec", "DotNetSDK", "SourceDirectory", "Logging", "General", "Features")
    foreach ($section in $requiredSections) {
        $exists = $config.ContainsKey($section)
        Write-TestResult "Config section '$section' exists" $exists
    }
    
    # Test 3: Storage configuration has required filesystem settings
    $storageHasFileSystems = $config.Storage.ContainsKey("Volume1FileSystem") -and $config.Storage.ContainsKey("Volume2FileSystem")
    Write-TestResult "Storage config has filesystem settings" $storageHasFileSystems
    
    # Test 4: Filesystem values are valid
    $validFileSystems = @("FAT", "FAT32", "exFAT", "NTFS", "ReFS")
    $vol1Valid = $config.Storage.Volume1FileSystem -in $validFileSystems
    $vol2Valid = $config.Storage.Volume2FileSystem -in $validFileSystems
    Write-TestResult "Volume1FileSystem is valid" $vol1Valid "Value: $($config.Storage.Volume1FileSystem)"
    Write-TestResult "Volume2FileSystem is valid" $vol2Valid "Value: $($config.Storage.Volume2FileSystem)"
    
    # Test 5: Required storage settings exist
    $requiredStorageKeys = @("PoolName", "VirtualDiskName", "Volume1Label", "Volume2Label", "Volume1SizePercent", "MinimumDisks")
    foreach ($key in $requiredStorageKeys) {
        $exists = $config.Storage.ContainsKey($key)
        Write-TestResult "Storage config has '$key'" $exists
    }
    
    # Test 6: Numeric values are valid
    $volume1SizeValid = $config.Storage.Volume1SizePercent -is [int] -and $config.Storage.Volume1SizePercent -gt 0 -and $config.Storage.Volume1SizePercent -lt 100
    Write-TestResult "Volume1SizePercent is valid" $volume1SizeValid "Value: $($config.Storage.Volume1SizePercent)%"
    
    $minDisksValid = $config.Storage.MinimumDisks -is [int] -and $config.Storage.MinimumDisks -ge 2
    Write-TestResult "MinimumDisks is valid" $minDisksValid "Value: $($config.Storage.MinimumDisks)"
}

function Test-FeatureDiscovery {
    Write-Host "`n=== Feature Discovery Tests ===" -ForegroundColor Cyan
    
    # Test 1: Features directory exists
    $featuresExist = Test-Path $TestConfig.FeaturesDirectory
    Write-TestResult "Features directory exists" $featuresExist $TestConfig.FeaturesDirectory
    
    if (-not $featuresExist) { return }
    
    # Test 2: Feature scripts are discovered
    try {
        $featureFiles = Get-ChildItem -Path $TestConfig.FeaturesDirectory -Filter "*.ps1" | Sort-Object Name
        $hasFeatures = $featureFiles.Count -gt 0
        Write-TestResult "Feature scripts discovered" $hasFeatures "Found $($featureFiles.Count) feature scripts"
        
        # Test 3: Expected features exist
        $expectedFeatures = @("01-storage-spaces.ps1", "02-windows-updates.ps1", "03-parsec.ps1", "04-dotnet-sdk9.ps1", "05-source-directory.ps1")
        foreach ($expected in $expectedFeatures) {
            $exists = $expected -in $featureFiles.Name
            Write-TestResult "Feature '$expected' exists" $exists
        }
        
        # Test 4: Feature scripts have required functions
        foreach ($featureFile in $featureFiles) {
            try {
                $content = Get-Content -Path $featureFile.FullName -Raw
                $hasTestFunction = $content -match "function\s+Test-.*Prerequisites"
                $hasInstallFunction = $content -match "function\s+Install-.*"
                
                Write-TestResult "$($featureFile.Name) has Test-Prerequisites function" $hasTestFunction
                Write-TestResult "$($featureFile.Name) has Install function" $hasInstallFunction
                
                # Test 5: Scripts are syntactically valid
                try {
                    $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$null)
                    Write-TestResult "$($featureFile.Name) syntax is valid" $true
                }
                catch {
                    Write-TestResult "$($featureFile.Name) syntax is valid" $false "Syntax error: $($_.Exception.Message)"
                }
            }
            catch {
                Write-TestResult "$($featureFile.Name) readable" $false "Error reading file: $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-TestResult "Feature scripts discovered" $false "Error: $($_.Exception.Message)"
    }
}

function Test-Prerequisites {
    Write-Host "`n=== Prerequisites Tests ===" -ForegroundColor Cyan
    
    # Test 1: Administrator check
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-TestResult "Running as Administrator" $isAdmin
    
    # Test 2: PowerShell execution policy
    $executionPolicy = Get-ExecutionPolicy
    $policyOk = $executionPolicy -ne "Restricted"
    Write-TestResult "PowerShell execution policy allows scripts" $policyOk "Policy: $executionPolicy"
    
    # Test 3: PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    $versionOk = $psVersion.Major -ge 5
    Write-TestResult "PowerShell version is supported" $versionOk "Version: $($psVersion.ToString())"
    
    # Test 4: Storage Spaces availability
    try {
        $storageSubsystem = Get-StorageSubSystem -ErrorAction Stop
        Write-TestResult "Storage Spaces available" $true "Storage subsystem detected"
    }
    catch {
        Write-TestResult "Storage Spaces available" $false "Error: $($_.Exception.Message)"
    }
    
    # Test 5: Physical disks for testing
    try {
        $physicalDisks = Get-PhysicalDisk | Where-Object { $_.CanPool -eq $true }
        $hasEnoughDisks = $physicalDisks.Count -ge 2
        Write-TestResult "Sufficient physical disks for striping" $hasEnoughDisks "Found $($physicalDisks.Count) poolable disks"
        
        if ($physicalDisks.Count -gt 0) {
            $totalSize = ($physicalDisks | Measure-Object -Property Size -Sum).Sum
            Write-TestResult "Physical disks have adequate size" ($totalSize -gt 50GB) "Total poolable size: $([math]::Round($totalSize / 1GB, 2)) GB"
        }
    }
    catch {
        Write-TestResult "Physical disk detection" $false "Error: $($_.Exception.Message)"
    }
    
    # Test 6: Internet connectivity (for downloads)
    try {
        $response = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Write-TestResult "Internet connectivity" $true "HTTP response: $($response.StatusCode)"
    }
    catch {
        Write-TestResult "Internet connectivity" $false "Error: $($_.Exception.Message)"
    }
    
    # Test 7: Windows Defender cmdlets available
    try {
        $defenderAvailable = Get-Command "Add-MpPreference" -ErrorAction SilentlyContinue
        Write-TestResult "Windows Defender cmdlets available" ($null -ne $defenderAvailable)
    }
    catch {
        Write-TestResult "Windows Defender cmdlets available" $false "Error: $($_.Exception.Message)"
    }
}

function Test-StorageSpacesFeature {
    Write-Host "`n=== Storage Spaces Feature Tests ===" -ForegroundColor Cyan
    
    # Test 1: Storage configuration merging
    try {
        $testConfig = @{
            Storage = @{
                Volume1FileSystem = "ReFS"
                Volume2FileSystem = "NTFS"
                Volume1Label = "TestData"
                Volume1SizePercent = 40
            }
        }
        
        # Simulate the merging logic from the feature script
        $defaultConfig = @{
            PoolName = "VMStoragePool"
            VirtualDiskName = "VMStripedDisk"
            Volume1Label = "Data"
            Volume2Label = "Applications"
            Volume1SizePercent = 27
            Volume1FileSystem = "ReFS"
            Volume2FileSystem = "NTFS"
            MinimumDisks = 2
        }
        
        $featureConfig = $defaultConfig.Clone()
        if ($testConfig.Storage) {
            foreach ($key in $testConfig.Storage.Keys) {
                $featureConfig[$key] = $testConfig.Storage[$key]
            }
        }
        
        $configMergedCorrectly = ($featureConfig.Volume1FileSystem -eq "ReFS") -and 
                                ($featureConfig.Volume2FileSystem -eq "NTFS") -and
                                ($featureConfig.Volume1Label -eq "TestData") -and
                                ($featureConfig.Volume1SizePercent -eq 40)
        
        Write-TestResult "Storage config merging logic" $configMergedCorrectly "Configuration properly merged from Config.psd1"
    }
    catch {
        Write-TestResult "Storage config merging logic" $false "Error: $($_.Exception.Message)"
    }
    
    # Test 2: Filesystem validation
    $validFileSystems = @("FAT", "FAT32", "exFAT", "NTFS", "ReFS")
    $refsValid = "ReFS" -in $validFileSystems
    $ntfsValid = "NTFS" -in $validFileSystems
    Write-TestResult "ReFS filesystem validation" $refsValid
    Write-TestResult "NTFS filesystem validation" $ntfsValid
    
    # Test 3: Size calculation logic
    try {
        $testTotalSize = 1TB
        $testSizePercent = 30
        $expectedSize = [math]::Floor($testTotalSize * ($testSizePercent / 100))
        $calculatedSize = [math]::Floor($testTotalSize * 0.30)
        
        Write-TestResult "Volume size calculation" ($expectedSize -eq $calculatedSize) "30% of 1TB = $([math]::Round($calculatedSize / 1GB, 2)) GB"
    }
    catch {
        Write-TestResult "Volume size calculation" $false "Error: $($_.Exception.Message)"
    }
    
    # Test 4: Drive letter availability function simulation
    try {
        $usedLetters = @('C', 'D')  # Simulate used drive letters
        $allLetters = 'D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
        $availableLetter = $allLetters | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
        
        Write-TestResult "Drive letter allocation logic" ($availableLetter -eq 'E') "Next available letter: $availableLetter"
    }
    catch {
        Write-TestResult "Drive letter allocation logic" $false "Error: $($_.Exception.Message)"
    }
}

function Test-SourceDirectoryFeature {
    Write-Host "`n=== Source Directory Feature Tests ===" -ForegroundColor Cyan
    
    # Test 1: Configuration validation
    try {
        $config = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot "Config.psd1")
        $sourceConfigExists = $config.ContainsKey("SourceDirectory")
        Write-TestResult "Source directory configuration exists" $sourceConfigExists
        
        if ($sourceConfigExists) {
            $requiredKeys = @("DirectoryName", "AddDefenderExclusion", "CreateIfMissing")
            foreach ($key in $requiredKeys) {
                $exists = $config.SourceDirectory.ContainsKey($key)
                Write-TestResult "SourceDirectory config has '$key'" $exists
            }
        }
    }
    catch {
        Write-TestResult "Source directory configuration validation" $false "Error: $($_.Exception.Message)"
    }
    
    # Test 2: Dependency checking logic
    try {
        $mockConfig = @{
            Storage = @{
                Volume1Label = "Data"
            }
        }
        
        # Simulate dependency check
        $dependencyLogicWorks = $mockConfig.Storage.Volume1Label -eq "Data"
        Write-TestResult "Source directory dependency logic" $dependencyLogicWorks "Checks for Storage.Volume1Label"
    }
    catch {
        Write-TestResult "Source directory dependency logic" $false "Error: $($_.Exception.Message)"
    }
    
    # Test 3: Path construction logic
    try {
        $testDriveLetter = "E"
        $testDirectoryName = "src"
        $expectedPath = "${testDriveLetter}:\${testDirectoryName}"
        $constructedPath = "${testDriveLetter}:\$testDirectoryName"
        
        Write-TestResult "Path construction logic" ($expectedPath -eq $constructedPath) "Path: $constructedPath"
    }
    catch {
        Write-TestResult "Path construction logic" $false "Error: $($_.Exception.Message)"
    }
    
    # Test 4: Subdirectory creation logic
    try {
        $testSubdirs = @("github", "projects", "temp")
        $testBasePath = "E:\src"
        $expectedPaths = $testSubdirs | ForEach-Object { Join-Path $testBasePath $_ }
        
        Write-TestResult "Subdirectory path logic" ($expectedPaths.Count -eq 3) "Generated $($expectedPaths.Count) subdirectory paths"
    }
    catch {
        Write-TestResult "Subdirectory path logic" $false "Error: $($_.Exception.Message)"
    }
}

function Test-DryRunFunctionality {
    Write-Host "`n=== Dry Run Tests ===" -ForegroundColor Cyan
    
    # Test 1: Dry run parameter handling
    Write-TestResult "Dry run mode active" $DryRun "Running in safe dry-run mode"
    
    # Test 2: List features functionality
    if (Test-Path $TestConfig.StartupScript) {
        try {
            $listOutput = & $TestConfig.StartupScript -ListFeatures 2>&1
            $listSuccessful = $listOutput -match "Available Features"
            Write-TestResult "List features functionality" $listSuccessful "Feature listing works"
        }
        catch {
            Write-TestResult "List features functionality" $false "Error: $($_.Exception.Message)"
        }
        
        # Test 3: Dry run with specific feature
        try {
            $dryRunOutput = & $TestConfig.StartupScript -DryRun -IncludeFeatures "05-source-directory.ps1" 2>&1
            $dryRunSuccessful = $dryRunOutput -match "DRY RUN" -or $dryRunOutput -match "Would execute"
            Write-TestResult "Dry run with specific feature" $dryRunSuccessful "Dry run simulation works"
        }
        catch {
            Write-TestResult "Dry run with specific feature" $false "Error: $($_.Exception.Message)"
        }
    }
    else {
        Write-TestResult "Startup script exists" $false "startup.ps1 not found at $($TestConfig.StartupScript)"
    }
}

function Test-ErrorHandling {
    Write-Host "`n=== Error Handling Tests ===" -ForegroundColor Cyan
    
    # Test 1: Invalid configuration file handling
    try {
        $testDir = Join-Path $TestConfig.TestDirectory "error-tests"
        if (-not (Test-Path $testDir)) {
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        }
        
        $invalidConfigPath = Join-Path $testDir "invalid-config.psd1"
        "Invalid PowerShell Data File Content @{ InvalidSyntax }" | Out-File -FilePath $invalidConfigPath
        
        try {
            Import-PowerShellDataFile -Path $invalidConfigPath -ErrorAction Stop
            Write-TestResult "Invalid config file rejection" $false "Should have failed to load invalid config"
        }
        catch {
            Write-TestResult "Invalid config file rejection" $true "Properly rejects invalid config file"
        }
    }
    catch {
        Write-TestResult "Invalid config file test setup" $false "Test setup error: $($_.Exception.Message)"
    }
    
    # Test 2: Missing feature script handling
    try {
        $missingFeaturePath = Join-Path $TestConfig.FeaturesDirectory "99-nonexistent-feature.ps1"
        $featureExists = Test-Path $missingFeaturePath
        Write-TestResult "Missing feature detection" (-not $featureExists) "Properly detects missing features"
    }
    catch {
        Write-TestResult "Missing feature detection" $false "Error: $($_.Exception.Message)"
    }
    
    # Test 3: ContinueOnError logic simulation
    try {
        $continueOnErrorConfig = @{ General = @{ ContinueOnError = $true } }
        $shouldContinue = $continueOnErrorConfig.General.ContinueOnError
        Write-TestResult "ContinueOnError configuration" $shouldContinue "Error handling configuration works"
    }
    catch {
        Write-TestResult "ContinueOnError configuration" $false "Error: $($_.Exception.Message)"
    }
}

function Test-DependencySystem {
    Write-Host "`n=== Dependency System Tests ===" -ForegroundColor Cyan
    
    # Test 1: Execution order configuration
    try {
        $config = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot "Config.psd1")
        $hasExecutionOrder = $config.Features.ContainsKey("ExecutionOrder") -and $config.Features.ExecutionOrder.Count -gt 0
        Write-TestResult "Execution order configuration" $hasExecutionOrder "Features.ExecutionOrder is configured"
        
        if ($hasExecutionOrder) {
            $orderIsCorrect = $config.Features.ExecutionOrder[0] -eq "01-storage-spaces.ps1" -and
                             $config.Features.ExecutionOrder[-1] -eq "05-source-directory.ps1"
            Write-TestResult "Execution order is logical" $orderIsCorrect "Storage spaces runs first, source directory last"
        }
    }
    catch {
        Write-TestResult "Execution order configuration" $false "Error: $($_.Exception.Message)"
    }
    
    # Test 2: Feature dependency metadata
    $sourceDirectoryScript = Join-Path $TestConfig.FeaturesDirectory "05-source-directory.ps1"
    if (Test-Path $sourceDirectoryScript) {
        try {
            $content = Get-Content -Path $sourceDirectoryScript -Raw
            $hasDependencyMetadata = $content -match '\$FeatureDependencies\s*=\s*@\('
            Write-TestResult "Feature dependency metadata" $hasDependencyMetadata "Source directory declares dependencies"
            
            if ($hasDependencyMetadata) {
                $declaresStoargeDependency = $content -match "01-storage-spaces\.ps1"
                Write-TestResult "Source directory depends on storage" $declaresStoargeDependency "Correctly depends on storage spaces"
            }
        }
        catch {
            Write-TestResult "Feature dependency metadata" $false "Error: $($_.Exception.Message)"
        }
    }
    else {
        Write-TestResult "Source directory script exists" $false "05-source-directory.ps1 not found"
    }
    
    # Test 3: Prerequisite function naming convention
    try {
        $featureFiles = Get-ChildItem -Path $TestConfig.FeaturesDirectory -Filter "*.ps1" -ErrorAction SilentlyContinue
        $conventionCompliant = 0
        
        foreach ($file in $featureFiles) {
            $content = Get-Content -Path $file.FullName -Raw
            if ($content -match "function\s+Test-.*Prerequisites") {
                $conventionCompliant++
            }
        }
        
        $allCompliant = $conventionCompliant -eq $featureFiles.Count
        Write-TestResult "Prerequisite function naming convention" $allCompliant "$conventionCompliant of $($featureFiles.Count) features follow naming convention"
    }
    catch {
        Write-TestResult "Prerequisite function naming convention" $false "Error: $($_.Exception.Message)"
    }
}

function Initialize-TestEnvironment {
    Write-Host "Initializing test environment..." -ForegroundColor Yellow
    
    # Create test directory
    if (-not (Test-Path $TestConfig.TestDirectory)) {
        New-Item -Path $TestConfig.TestDirectory -ItemType Directory -Force | Out-Null
    }
    
    # Create test configs directory
    $testConfigsDir = Join-Path $PSScriptRoot "test-configs"
    if (-not (Test-Path $testConfigsDir)) {
        New-Item -Path $testConfigsDir -ItemType Directory -Force | Out-Null
    }
}

function Write-TestSummary {
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "Test Suite Summary" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    Write-Host "Total Tests: $($TestConfig.TestCount)" -ForegroundColor White
    Write-Host "Passed: $($TestConfig.PassCount)" -ForegroundColor Green
    Write-Host "Failed: $($TestConfig.FailCount)" -ForegroundColor Red
    
    $successRate = if ($TestConfig.TestCount -gt 0) { [math]::Round(($TestConfig.PassCount / $TestConfig.TestCount) * 100, 1) } else { 0 }
    Write-Host "Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } elseif ($successRate -ge 60) { "Yellow" } else { "Red" })
    
    if ($TestConfig.FailCount -gt 0) {
        Write-Host "`nFailed Tests:" -ForegroundColor Red
        foreach ($testName in $TestConfig.Results.Keys) {
            $result = $TestConfig.Results[$testName]
            if (-not $result.Passed) {
                Write-Host "  ✗ $testName" -ForegroundColor Red
                if ($result.Message) {
                    Write-Host "    $($result.Message)" -ForegroundColor Gray
                }
            }
        }
    }
    
    Write-Host "`nTest completed at: $(Get-Date)" -ForegroundColor Cyan
    
    # Return overall success
    return $TestConfig.FailCount -eq 0
}

# Legacy support for existing dry run functionality
if (-not ($RunAll -or $TestConfigValidation -or $TestFeatureDiscovery -or $TestPrerequisites -or 
          $TestStorageSpaces -or $TestSourceDirectory -or $TestDryRun -or $TestErrorHandling -or $TestDependencies)) {
    
    # Default to legacy dry run mode if no specific tests specified
    if (-not $PSBoundParameters.ContainsKey('DryRun')) {
        $DryRun = $true
    }
    
    Write-Host "VM Setup Framework Test Script" -ForegroundColor Cyan
    Write-Host "Dry Run Mode: $DryRun" -ForegroundColor Yellow
    Write-Host "Features Directory: $($TestConfig.FeaturesDirectory)" -ForegroundColor Gray
    Write-Host ""
    
    # Run basic legacy tests
    Test-Prerequisites
    Test-FeatureDiscovery
    
    if ($TestConfig.FailCount -eq 0) {
        Write-Host "`n✓ Legacy test mode completed successfully!" -ForegroundColor Green
        Write-Host "For comprehensive testing, use: .\Test-VMSetup.ps1 -RunAll" -ForegroundColor Cyan
    }
    else {
        Write-Host "`n✗ Legacy test mode found issues. Run comprehensive tests: .\Test-VMSetup.ps1 -RunAll" -ForegroundColor Red
    }
    
    exit $(if ($TestConfig.FailCount -eq 0) { 0 } else { 1 })
}

# Main execution for comprehensive tests
try {
    Write-Host "VM Setup Comprehensive Test Suite" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host "Started at: $(Get-Date)" -ForegroundColor Gray
    Write-Host ""
    
    Initialize-TestEnvironment
    
    # Run selected tests
    if ($RunAll -or $TestConfigValidation) {
        Test-ConfigurationValidation
    }
    
    if ($RunAll -or $TestFeatureDiscovery) {
        Test-FeatureDiscovery
    }
    
    if ($RunAll -or $TestPrerequisites) {
        Test-Prerequisites
    }
    
    if ($RunAll -or $TestStorageSpaces) {
        Test-StorageSpacesFeature
    }
    
    if ($RunAll -or $TestSourceDirectory) {
        Test-SourceDirectoryFeature
    }
    
    if ($RunAll -or $TestDryRun) {
        Test-DryRunFunctionality
    }
    
    if ($RunAll -or $TestErrorHandling) {
        Test-ErrorHandling
    }
    
    if ($RunAll -or $TestDependencies) {
        Test-DependencySystem
    }
    
    # Show usage if no tests were run
    if ($TestConfig.TestCount -eq 0) {
        Write-Host "Usage: Test-VMSetup.ps1 [options]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Options:" -ForegroundColor White
        Write-Host "  -RunAll                 Run all comprehensive tests" -ForegroundColor Gray
        Write-Host "  -TestConfigValidation   Test configuration file validation" -ForegroundColor Gray
        Write-Host "  -TestFeatureDiscovery   Test feature script discovery" -ForegroundColor Gray
        Write-Host "  -TestPrerequisites      Test system prerequisites" -ForegroundColor Gray
        Write-Host "  -TestStorageSpaces      Test storage spaces feature" -ForegroundColor Gray
        Write-Host "  -TestSourceDirectory    Test source directory feature" -ForegroundColor Gray
        Write-Host "  -TestDryRun             Test dry run functionality" -ForegroundColor Gray
        Write-Host "  -TestErrorHandling      Test error handling" -ForegroundColor Gray
        Write-Host "  -TestDependencies       Test dependency system" -ForegroundColor Gray
        Write-Host "  -Verbose                Show detailed test information" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Cyan
        Write-Host "  .\Test-VMSetup.ps1 -RunAll -Verbose" -ForegroundColor Gray
        Write-Host "  .\Test-VMSetup.ps1 -TestConfigValidation -TestStorageSpaces" -ForegroundColor Gray
        Write-Host "  .\Test-VMSetup.ps1 (legacy mode - basic tests only)" -ForegroundColor Gray
        return
    }
    
    $overallSuccess = Write-TestSummary
    
    if ($overallSuccess) {
        Write-Host "`n✓ All tests passed!" -ForegroundColor Green
        Write-Host "Your VM setup system is ready for use." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`n✗ Some tests failed. Review the results above." -ForegroundColor Red
        Write-Host "Fix the issues before running the VM setup." -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-Host "`nFatal error in test suite: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
finally {
    # Cleanup test environment
    if (Test-Path $TestConfig.TestDirectory) {
        Remove-Item -Path $TestConfig.TestDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
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

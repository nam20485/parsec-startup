# Unit Tests for Configuration Merging
# Tests the configuration merging logic used in feature scripts

function Test-ConfigMerging {
    Write-Host "Testing Configuration Merging Logic..." -ForegroundColor Cyan
    
    # Test Case 1: Basic merging
    $defaultConfig = @{
        PoolName = "DefaultPool"
        VirtualDiskName = "DefaultDisk"
        Volume1FileSystem = "NTFS"
    }
    
    $userConfig = @{
        Storage = @{
            PoolName = "UserPool"
            Volume1FileSystem = "ReFS"
            NewSetting = "UserValue"
        }
    }
    
    # Simulate the merging logic from feature scripts
    $featureConfig = $defaultConfig.Clone()
    if ($userConfig.Storage) {
        foreach ($key in $userConfig.Storage.Keys) {
            $featureConfig[$key] = $userConfig.Storage[$key]
        }
    }
    
    # Assertions
    $test1 = $featureConfig.PoolName -eq "UserPool"
    $test2 = $featureConfig.Volume1FileSystem -eq "ReFS"
    $test3 = $featureConfig.VirtualDiskName -eq "DefaultDisk"  # Should keep default
    $test4 = $featureConfig.NewSetting -eq "UserValue"  # Should add new setting
    
    Write-Host "  Override existing setting: $(if($test1){'✓'}else{'✗'})" -ForegroundColor $(if($test1){'Green'}else{'Red'})
    Write-Host "  Override filesystem setting: $(if($test2){'✓'}else{'✗'})" -ForegroundColor $(if($test2){'Green'}else{'Red'})
    Write-Host "  Preserve unmodified default: $(if($test3){'✓'}else{'✗'})" -ForegroundColor $(if($test3){'Green'}else{'Red'})
    Write-Host "  Add new user setting: $(if($test4){'✓'}else{'✗'})" -ForegroundColor $(if($test4){'Green'}else{'Red'})
    
    return $test1 -and $test2 -and $test3 -and $test4
}

function Test-FilesystemValidation {
    Write-Host "Testing Filesystem Validation..." -ForegroundColor Cyan
    
    $validFileSystems = @("FAT", "FAT32", "exFAT", "NTFS", "ReFS")
    
    $test1 = "ReFS" -in $validFileSystems
    $test2 = "NTFS" -in $validFileSystems
    $test3 = "InvalidFS" -notin $validFileSystems
    $test4 = "" -notin $validFileSystems
    
    Write-Host "  ReFS is valid: $(if($test1){'✓'}else{'✗'})" -ForegroundColor $(if($test1){'Green'}else{'Red'})
    Write-Host "  NTFS is valid: $(if($test2){'✓'}else{'✗'})" -ForegroundColor $(if($test2){'Green'}else{'Red'})
    Write-Host "  Invalid filesystem rejected: $(if($test3){'✓'}else{'✗'})" -ForegroundColor $(if($test3){'Green'}else{'Red'})
    Write-Host "  Empty string rejected: $(if($test4){'✓'}else{'✗'})" -ForegroundColor $(if($test4){'Green'}else{'Red'})
    
    return $test1 -and $test2 -and $test3 -and $test4
}

function Test-SizeCalculation {
    Write-Host "Testing Size Calculation..." -ForegroundColor Cyan
    
    $totalSize = 1TB
    $sizePercent = 30
    
    # Test the calculation logic from storage spaces
    $calculatedSize = [math]::Floor($totalSize * ($sizePercent / 100))
    $expectedSize = 300GB
    
    $test1 = $calculatedSize -eq $expectedSize
    $test2 = $calculatedSize -gt 0
    $test3 = $calculatedSize -lt $totalSize
    
    Write-Host "  Correct calculation (30% of 1TB = 300GB): $(if($test1){'✓'}else{'✗'})" -ForegroundColor $(if($test1){'Green'}else{'Red'})
    Write-Host "  Size is positive: $(if($test2){'✓'}else{'✗'})" -ForegroundColor $(if($test2){'Green'}else{'Red'})
    Write-Host "  Size is less than total: $(if($test3){'✓'}else{'✗'})" -ForegroundColor $(if($test3){'Green'}else{'Red'})
    
    return $test1 -and $test2 -and $test3
}

# Run unit tests
Write-Host "VM Setup Unit Tests" -ForegroundColor Yellow
Write-Host "===================" -ForegroundColor Yellow
Write-Host ""

$configTest = Test-ConfigMerging
$filesystemTest = Test-FilesystemValidation
$sizeTest = Test-SizeCalculation

Write-Host ""
Write-Host "Unit Test Results:" -ForegroundColor Yellow
Write-Host "  Configuration Merging: $(if($configTest){'✓ PASS'}else{'✗ FAIL'})" -ForegroundColor $(if($configTest){'Green'}else{'Red'})
Write-Host "  Filesystem Validation: $(if($filesystemTest){'✓ PASS'}else{'✗ FAIL'})" -ForegroundColor $(if($filesystemTest){'Green'}else{'Red'})
Write-Host "  Size Calculation: $(if($sizeTest){'✓ PASS'}else{'✗ FAIL'})" -ForegroundColor $(if($sizeTest){'Green'}else{'Red'})

$allPassed = $configTest -and $filesystemTest -and $sizeTest
Write-Host ""
Write-Host "Overall Result: $(if($allPassed){'✓ ALL TESTS PASSED'}else{'✗ SOME TESTS FAILED'})" -ForegroundColor $(if($allPassed){'Green'}else{'Red'})

exit $(if($allPassed) { 0 } else { 1 })

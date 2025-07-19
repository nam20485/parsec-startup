# Feature: Source Directory Setup
# Creates source code directory on data volume and configures Windows Defender exclusions

#Requires -RunAsAdministrator

param(
    [hashtable]$Config = @{},
    [switch]$Verbose = $false
)

# Feature metadata
$FeatureName = "Source Directory Setup"
$FeatureDescription = "Creates source code directory and configures Windows Defender exclusions"
$FeatureDependencies = @("01-storage-spaces.ps1")  # Requires storage spaces to be set up first

function Test-SourceDirectoryPrerequisites {
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This feature requires administrator privileges"
    }

    # Check if the data volume exists (Volume1 from storage spaces)
    $dataVolume = Get-Volume | Where-Object { $_.FileSystemLabel -eq $Config.Storage.Volume1Label }
    if (-not $dataVolume) {
        throw "Data volume '$($Config.Storage.Volume1Label)' not found. Storage spaces feature must be run first."
    }

    return $true
}

function Install-SourceDirectory {
    param(
        [hashtable]$FeatureConfig
    )

    try {
        Write-Host "Setting up source directory..." -ForegroundColor Yellow

        # Get the data volume
        $dataVolume = Get-Volume | Where-Object { $_.FileSystemLabel -eq $Config.Storage.Volume1Label }
        if (-not $dataVolume.DriveLetter) {
            throw "Data volume does not have a drive letter assigned"
        }

        $driveLetter = $dataVolume.DriveLetter
        $sourceDirectoryPath = "${driveLetter}:\$($FeatureConfig.DirectoryName)"

        Write-Host "Data volume drive letter: $driveLetter" -ForegroundColor Green
        Write-Host "Source directory path: $sourceDirectoryPath" -ForegroundColor Green

        # Create the source directory if it doesn't exist
        if ($FeatureConfig.CreateIfMissing) {
            if (-not (Test-Path $sourceDirectoryPath)) {
                Write-Host "Creating source directory: $sourceDirectoryPath" -ForegroundColor Yellow
                $directory = New-Item -Path $sourceDirectoryPath -ItemType Directory -Force
                Write-Host "Source directory created successfully" -ForegroundColor Green
            } else {
                Write-Host "Source directory already exists: $sourceDirectoryPath" -ForegroundColor Green
            }
        }

        # Create additional subdirectories if specified
        if ($FeatureConfig.Subdirectories -and $FeatureConfig.Subdirectories.Count -gt 0) {
            Write-Host "Creating subdirectories..." -ForegroundColor Yellow
            foreach ($subdir in $FeatureConfig.Subdirectories) {
                $subdirPath = Join-Path $sourceDirectoryPath $subdir
                if (-not (Test-Path $subdirPath)) {
                    Write-Host "Creating subdirectory: $subdirPath" -ForegroundColor Yellow
                    New-Item -Path $subdirPath -ItemType Directory -Force | Out-Null
                    Write-Host "Subdirectory created: $subdir" -ForegroundColor Green
                } else {
                    Write-Host "Subdirectory already exists: $subdir" -ForegroundColor Green
                }
            }
        }

        # Add Windows Defender exclusion
        if ($FeatureConfig.AddDefenderExclusion) {
            Write-Host "Adding Windows Defender exclusion for source directory..." -ForegroundColor Yellow
            
            try {
                # Check if exclusion already exists
                $existingExclusions = Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
                if ($existingExclusions -and $existingExclusions -contains $sourceDirectoryPath) {
                    Write-Host "Windows Defender exclusion already exists for: $sourceDirectoryPath" -ForegroundColor Green
                } else {
                    # Add the exclusion
                    Add-MpPreference -ExclusionPath $sourceDirectoryPath
                    Write-Host "Windows Defender exclusion added for: $sourceDirectoryPath" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "Failed to add Windows Defender exclusion: $($_.Exception.Message)"
                if (-not $Config.General.ContinueOnError) {
                    throw
                }
            }
        }

        Write-Host "Source directory setup completed successfully" -ForegroundColor Green
        
        return @{
            Success = $true
            DirectoryPath = $sourceDirectoryPath
            DriveLetter = $driveLetter
            DefenderExclusion = $FeatureConfig.AddDefenderExclusion
        }
    }
    catch {
        Write-Error "Failed to set up source directory: $($_.Exception.Message)"
        throw
    }
}

# Main execution
try {
    Write-Host "Starting $FeatureName..." -ForegroundColor Cyan
    
    # Test prerequisites
    Test-SourceDirectoryPrerequisites

    # Default configuration
    $defaultConfig = @{
        DirectoryName = "src"
        AddDefenderExclusion = $true
        CreateIfMissing = $true
        Subdirectories = @()
        Permissions = ""
    }

    # Merge with provided config
    $featureConfig = $defaultConfig.Clone()
    if ($Config.SourceDirectory) {
        foreach ($key in $Config.SourceDirectory.Keys) {
            $featureConfig[$key] = $Config.SourceDirectory[$key]
        }
    }

    if ($Verbose -or $Config.Logging.Verbose) {
        Write-Host "Feature configuration:" -ForegroundColor Gray
        $featureConfig | Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor Gray
    }

    # Install source directory
    $result = Install-SourceDirectory -FeatureConfig $featureConfig

    Write-Host "$FeatureName completed successfully!" -ForegroundColor Green
    Write-Host "Source directory: $($result.DirectoryPath)" -ForegroundColor Green
    
    if ($result.DefenderExclusion) {
        Write-Host "Windows Defender exclusion: Enabled" -ForegroundColor Green
    }

    return $result
}
catch {
    Write-Error "$FeatureName failed: $($_.Exception.Message)"
    if ($Config.Logging.Verbose) {
        Write-Error $_.Exception.StackTrace
    }
    throw
}
#Requires -RunAsAdministrator

# ============================================================================
# Applications
# ============================================================================

$packages = @(
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MixedReality.Portal'
    'Microsoft.BingSearch'
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.WindowsCamera'
    'Clipchamp.Clipchamp'
    'Microsoft.WindowsAlarms'
    'Microsoft.549981C3F5F10'
    'Microsoft.GetHelp'
    'Microsoft.Windows.DevHome'
    'MicrosoftCorporationII.MicrosoftFamily'
    'microsoft.windowscommunicationsapps'
    'Microsoft.SkypeApp'
    'MSTeams'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.OutlookForWindows'
    'Microsoft.MSPaint'
    'Microsoft.Paint'
    'Microsoft.People'
    'Microsoft.PowerAutomateDesktop'
    'MicrosoftCorporationII.QuickAssist'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.GamingApp'
    'Microsoft.XboxApp'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxGameOverlay'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.ZuneVideo'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.MicrosoftStickyNotes'
    'Microsoft.Getstarted'
    'Microsoft.Todos'
    'Microsoft.YourPhone'
    'Microsoft.Office.OneNote'
)

$capabilities = @(
    'App.Support.QuickAssist'
    'App.StepsRecorder'
    'Microsoft.Windows.MSPaint'
    'OpenSSH.Server'
)

$optionalFeatures = @(
    'Microsoft-Windows-Subsystem-Linux'
    'NetFx3'
    'Containers-DisposableClientVM'
    'Recall'
)

$specialApps = @(
    'OneNote'
)

# ============================================================================
# MAIN
# ============================================================================

Write-Output "Starting bloat removal process"

# Stop Microsoft Teams process before removal to avoid long removal delays
Get-Process | Where-Object { $_.Name -like '*teams*' } | Stop-Process -Force -ErrorAction SilentlyContinue

# Discover all packages upfront (single query each)
Write-Output "Discovering all packages..."
$allInstalled = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
$allProvisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

$packagesToRemove = @()
$provisionedToRemove = @()
$notFound = @()

foreach ($package in $packages)
{
    $installed = @($allInstalled | Where-Object Name -EQ $package)
    $provisioned = @($allProvisioned | Where-Object DisplayName -EQ $package)

    if ($installed)
    {
        foreach ($pkg in $installed)
        {
            Write-Output "Queuing installed package: $($pkg.PackageFullName)"
        }
        $packagesToRemove += $installed.PackageFullName
    }
    if ($provisioned)
    {
        foreach ($pkg in $provisioned)
        {
            Write-Output "Queuing provisioned package: $($pkg.PackageName)"
        }
        $provisionedToRemove += $provisioned.PackageName
    }

    if (-not $installed -and -not $provisioned)
    {
        $notFound += $package
    }
}

if ($notFound.Count -gt 0)
{
    Write-Output "Packages not found: $($notFound -join ', ')"
}

# Deprovision first — critical for Win10 (Remove-AppxPackage -AllUsers fails with 0x80070002 otherwise)
Invoke-RunspacePool -Items $provisionedToRemove -MaxThreads 10 -Label "provisioned packages" `
    -ScriptBlock {
    param($p)
    try
    {
        Remove-AppxProvisionedPackage -Online -PackageName $p -ErrorAction Stop | Out-Null
        @{ Name = $p; Success = $true; Error = $null }
    }
    catch
    {
        @{ Name = $p; Success = $false; Error = $_.Exception.Message }
    }
} `
    -SuccessFormat "Deprovisioned: {0}" `
    -FailFormat "Failed to deprovision {0}: {1}"

# Remove installed packages (for all users)
Invoke-RunspacePool -Items $packagesToRemove -MaxThreads 10 -Label "installed packages" `
    -ScriptBlock {
    param($p)
    try
    {
        Remove-AppxPackage -Package $p -AllUsers -ErrorAction Stop
        @{ Name = $p; Success = $true; Error = $null }
    }
    catch
    {
        @{ Name = $p; Success = $false; Error = $_.Exception.Message }
    }
} `
    -SuccessFormat "Removed installed package: {0}" `
    -FailFormat "Failed to remove installed package {0}: {1}"

# Capabilities — single DISM enumeration, then parallel removal
Write-Output "Processing capabilities..."
$allCaps = Get-WindowsCapability -Online -ErrorAction SilentlyContinue
$capNamesToRemove = @()

foreach ($capability in $capabilities)
{
    $matching = @($allCaps | Where-Object { $_.Name -like "$capability*" -and $_.State -eq "Installed" })
    if ($matching)
    {
        $matching | ForEach-Object { Write-Output "Queuing capability: $($_.Name)" }
        $capNamesToRemove += $matching.Name
    }
    else
    {
        Write-Output "Capability not found or not installed: $capability"
    }
}

Invoke-RunspacePool -Items $capNamesToRemove -MaxThreads 5 -Label "capabilities" `
    -ScriptBlock {
    param($name)
    try
    {
        Remove-WindowsCapability -Online -Name $name -ErrorAction Stop | Out-Null
        @{ Name = $name; Success = $true; Error = $null }
    }
    catch
    {
        @{ Name = $name; Success = $false; Error = $_.Exception.Message }
    }
} `
    -SuccessFormat "Removed capability: {0}" `
    -FailFormat "Failed to remove capability {0}: {1}"

# Optional features — batch disable
Write-Output "Processing optional features..."
$enabledFeatures = @()
foreach ($feature in $optionalFeatures)
{
    $existing = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
    if ($existing -and $existing.State -eq "Enabled")
    {
        $enabledFeatures += $feature
    }
    else
    {
        Write-Output "Feature not found or not enabled: $feature"
    }
}

if ($enabledFeatures.Count -gt 0)
{
    Write-Output "Disabling features: $($enabledFeatures -join ', ')"
    Disable-WindowsOptionalFeature -Online -FeatureName $enabledFeatures -NoRestart -ErrorAction SilentlyContinue | Out-Null
}

# Special apps — registry-based uninstall
if ($specialApps.Count -gt 0)
{
    Write-Output "Processing special apps..."

    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($specialApp in $specialApps)
    {
        Write-Output "Processing special app: $specialApp"

        $processNames = switch ($specialApp)
        {
            'OneNote'
            {
                @('OneNote', 'ONENOTE', 'ONENOTEM')
            }
            default
            {
                Write-Output "Unknown special app: $specialApp"; continue
            }
        }

        foreach ($name in $processNames)
        {
            Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }

        $uninstalled = $false
        foreach ($basePath in $uninstallPaths)
        {
            $keys = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -like "$specialApp*" }

            foreach ($key in $keys)
            {
                $uninstallString = (Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue).UninstallString
                if (-not $uninstallString)
                {
                    continue
                }

                Write-Output "Found uninstall string: $uninstallString"
                $silent = if ($uninstallString -like '*OfficeClickToRun.exe*')
                {
                    'DisplayLevel=False'
                }
                else
                {
                    '/silent'
                }

                if ($uninstallString -match '^"([^"]+)"(.*)$')
                {
                    Start-Process -FilePath $matches[1] -ArgumentList "$($matches[2].Trim()) $silent" -NoNewWindow -Wait -ErrorAction SilentlyContinue
                }
                else
                {
                    Start-Process -FilePath $uninstallString -ArgumentList $silent -NoNewWindow -Wait -ErrorAction SilentlyContinue
                }

                $uninstalled = $true
                Write-Output "Completed uninstall for $specialApp"
            }
        }

        if (-not $uninstalled)
        {
            Write-Output "No uninstall strings found for $specialApp"
        }
    }
}

# ============================================================================
# REGISTRY SETTINGS TO PREVENT ISSUES AND BUGS
# ============================================================================

$xboxPackages = @('Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxGameOverlay')
$hasXboxPackages = $packages | Where-Object { $xboxPackages -contains $_ }

if ($hasXboxPackages)
{
    Write-Output "Applying registry settings to prevent post-removal issues..."

    try
    {
        $runningAsSystem = ($env:USERNAME -eq "SYSTEM" -or $env:USERPROFILE -like "*\system32\config\systemprofile")

        if ($runningAsSystem)
        {
            Write-Output "Running as SYSTEM - detecting logged-in user..."
            $loggedInUser = (Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName

            if ($loggedInUser -and $loggedInUser -ne "NT AUTHORITY\SYSTEM")
            {
                $username = $loggedInUser.Split('\\')[1]
                $sid = $null
                $profListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
                foreach ($profKey in Get-ChildItem $profListPath -ErrorAction SilentlyContinue)
                {
                    $profPath = (Get-ItemProperty $profKey.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
                    if ($profPath -and $profPath.EndsWith("\$username"))
                    {
                        $sid = $profKey.PSChildName
                        break
                    }
                }
                if ($sid)
                {
                    Write-Log "Applying settings for user: $username (SID: $sid)"
                    reg add "HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /f /t REG_DWORD /v "AppCaptureEnabled" /d 0 2>$null | Out-Null
                    reg add "HKU\$sid\System\GameConfigStore" /f /t REG_DWORD /v "GameDVR_Enabled" /d 0 2>$null | Out-Null
                    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /f /t REG_DWORD /v "AllowGameDVR" /d 0 2>$null | Out-Null
                    Write-Output "Xbox Game DVR registry settings applied successfully"
                }
                else
                {
                    Write-Output "Warning: Could not resolve SID for user: $username"
                }
            }
            else
            {
                Write-Output "Warning: Could not detect logged-in user for registry settings"
            }
        }
        else
        {
            Write-Output "Running as user - applying settings directly to HKCU"
            reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /f /t REG_DWORD /v "AppCaptureEnabled" /d 0 2>$null | Out-Null
            reg add "HKCU\System\GameConfigStore" /f /t REG_DWORD /v "GameDVR_Enabled" /d 0 2>$null | Out-Null
            reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /f /t REG_DWORD /v "AllowGameDVR" /d 0 2>$null | Out-Null
            Write-Output "Xbox Game DVR registry settings applied successfully"
        }
    }
    catch
    {
        Write-Output "Warning: Could not apply Xbox Game DVR registry settings: $($_.Exception.Message)"
    }
}

Write-Output "Bloat removal process completed"

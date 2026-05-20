#Requires -RunAsAdministrator
# ==============================================================================
# Define the OS Cleanup Script Block
# ==============================================================================
$OBLITERATE_BLOAT = {
    [CmdletBinding()]
    param()

    Write-Host "--- Starting Windows 11 Audit Mode Cleanup Script Block ---" -ForegroundColor Cyan

    # 1. Targeted AppX/Provisioned Packages
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

    # 2. Windows Capabilities (Features on Demand)
    $capabilities = @(
        'App.Support.QuickAssist'
        'App.StepsRecorder'
        'Microsoft.Windows.MSPaint'
        'OpenSSH.Server'
    )

    # 3. Optional Windows Features
    $optionalFeatures = @(
        'Microsoft-Windows-Subsystem-Linux'
        'NetFx3'
        'Containers-DisposableClientVM'
        'Recall'
    )

    # Execute Provisioned/AppX Removal
    Write-Host "`n[+] Purging AppX and Provisioned Packages..." -ForegroundColor Yellow
    foreach ($target in $packages)
    {
        $provApp = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $target -or $_.PackageName -like "*$target*" }
        if ($provApp)
        {
            Write-Host "    Removing provisioned template: $($provApp.DisplayName)" -ForegroundColor LightGray
            Remove-AppxProvisionedPackage -Online -PackageName $provApp.PackageName -ErrorAction SilentlyContinue
        }

        $appx = Get-AppxPackage -Name "*$target*" -AllUsers
        if ($appx)
        {
            foreach ($app in $appx)
            {
                Write-Host "    Removing active AppX package: $($app.Name)" -ForegroundColor LightGray
                Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            }
        }
    }

    # Execute Capability Removal
    Write-Host "`n[+] Purging Windows Capabilities..." -ForegroundColor Yellow
    foreach ($cap in $capabilities)
    {
        $liveCap = Get-WindowsCapability -Online | Where-Object { $_.Name -like "$cap*" -and $_.State -eq "Installed" }
        if ($liveCap)
        {
            Write-Host "    Removing Capability: $($liveCap.Name)" -ForegroundColor LightGray
            Remove-WindowsCapability -Online -Name $liveCap.Name -ErrorAction SilentlyContinue
        }
    }

    # Execute Optional Features Disabling
    Write-Host "`n[-] Disabling Optional Windows Features..." -ForegroundColor Yellow
    foreach ($feature in $optionalFeatures)
    {
        $liveFeature = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
        if ($liveFeature -and $liveFeature.State -eq "Enabled")
        {
            Write-Host "    Disabling Feature: $feature" -ForegroundColor LightGray
            Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue
        }
    }

    Write-Host "`n[✔] Script block cleanup task finished successfully." -ForegroundColor Green
}

# ==============================================================================
# Execution Trigger
# ==============================================================================
# Run the script block locally using the call operator (&)
& $OBLITERATE_BLOAT
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

# Get public and private function definition files.
[array]$Public  = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
[array]$Private = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue
$ThisModule = $(Get-Item $PSCommandPath).BaseName

# Dot source the Private functions
foreach ($import in $Private) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

[System.Collections.Arraylist]$ModulesToInstallAndImport = @()
if (Test-Path "$PSScriptRoot\module.requirements.psd1") {
    $ModuleManifestData = Import-PowerShellDataFile "$PSScriptRoot\module.requirements.psd1"
    $ModuleManifestData.Keys | Where-Object {$_ -ne "PSDependOptions"} | foreach {$null = $ModulesToinstallAndImport.Add($_)}
}

if ($ModulesToInstallAndImport.Count -gt 0) {
    # NOTE: If you're not sure if the Required Module is Locally Available or Externally Available,
    # add it the the -RequiredModules string array just to be certain
    $InvModDepSplatParams = @{
        RequiredModules                     = $ModulesToInstallAndImport
        InstallModulesNotAvailableLocally   = $True
        ErrorAction                         = "SilentlyContinue"
        WarningAction                       = "SilentlyContinue"
    }
    $ModuleDependenciesMap = InvokeModuleDependencies @InvModDepSplatParams
}

if (![bool]$(Get-Module UniversalDashboard.Community)) {
    try {
        Import-Module UniversalDashboard.Community -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -match "\.Net Framework") {
            try {
                Write-Host "Installing .Net Framework 4.7.2 ... This will take a little while, and you will need to restart afterwards..."
                $InstallDotNet47Result = Install-Program -ProgramName dotnet4.7.2 -ErrorAction Stop
            }
            catch {
                Write-Error $_
                Write-Warning ".Net Framework 4.7.2 was NOT installed successfully."
                Write-Warning "The $ThisModule Module will NOT be loaded. Please run`n    Remove-Module $ThisModule"
                $global:FunctionResult = "1"
                return
            }

            Write-Warning ".Net Framework 4.7.2 was installed successfully, however *****you must restart $env:ComputerName***** before using the $ThisModule Module! Halting!"
            return
        }
        else {
            Write-Error $_
            Write-Warning "The $ThisModule Module was NOT loaded successfully! Please run:`n    Remove-Module $ThisModule"
            $global:FunctionResult = "1"
            return
        }
    }
}

# Public Functions


<#
    .SYNOPSIS
        This function starts a PowerShell Universal Dashboard (Web-based GUI) instance on the specified port on the
        localhost. The Dashboard features a Network Monitor tool that pings the specified Remote Hosts in your Domain
        every 5 seconds and reports the results to the site.

    .DESCRIPTION
        See .SYNOPSIS

    .PARAMETER Port
        This parameter is OPTIONAL, however, it has a default value of 80.

        This parameter takes an integer between 1 and 32768 that represents the port on the localhost that the site
        will run on.

    .PARAMETER RemoveExistingPUD
        This parameter is OPTIONAL, however, it has a default value of $True.

        This parameter is a switch. If used, all running PowerShell Universal Dashboard instances will be removed
        prior to starting the Network Monitor Dashboard.

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Get-UDNetMon
        
#>
function Get-UDNetMon {
    Param (
        [Parameter(Mandatory=$False)]
        [ValidateRange(1,32768)]
        [int]$Port = 80,

        [Parameter(Mandatory=$False)]
        [switch]$RemoveExistingPUD = $True
    )

    # Remove all current running instances of PUD
    if ($RemoveExistingPUD) {
        Get-UDDashboard | Stop-UDDashboard
    }

    # Make sure we can resolve the $DomainName
    try {
        $DomainName = $(Get-CimInstance Win32_ComputerSystem).Domain
        $ResolveDomainInfo = [System.Net.Dns]::Resolve($DomainName)
    }
    catch {
        Write-Error "Unable to resolve domain '$DomainName'! Halting!"
        $global:FunctionResult = "1"
        return
    }

    # Get all Computers in Active Directory without the ActiveDirectory Module
    [System.Collections.ArrayList]$RemoteHostList = $(GetComputerObjectsInLDAP).Name
    if ($PSVersionTable.PSEdition -eq "Core") {
        [System.Collections.ArrayList]$RemoteHostList = $RemoteHostList | foreach {$_ -replace "CN=",""}
    }
    $null = $RemoteHostList.Insert(0,"Please Select a Server")


    [System.Collections.ArrayList]$Pages = @()

    # Create Home Page
    $HomePageContent = {
        New-UDLayout -Columns 1 -Content {
            New-UDCard -Title "Network Monitor" -Id "NMCard" -Text "Monitor Network" -Links @(
                New-UDLink -Text "Network Monitor" -Url "/NetworkMonitor" -Icon dashboard
            )
        }
    }
    $HomePage = New-UDPage -Name "Home" -Icon home -Content $HomePageContent
    $null = $Pages.Add($HomePage)

    # Create Network Monitor Page
    [scriptblock]$NMContentSB = {
        for ($i=1; $i -lt $RemoteHostList.Count; $i++) {
            New-UDInputField -Type 'radioButtons' -Name "Server$i" -Values $RemoteHostList[$i]
        }
    }
    [System.Collections.ArrayList]$paramStringPrep = @()
    for ($i=1; $i -lt $RemoteHostList.Count; $i++) {
        $StringToAdd = '$' + "Server$i"
        $null = $paramStringPrep.Add($StringToAdd)
    }
    $paramString = 'param(' + $($paramStringPrep -join ', ') + ')'
    $NMEndPointSBAsStringPrep = @(
        $paramString
        '[System.Collections.ArrayList]$SubmitButtonActions = @()'
        ''
        '    foreach ($kvpair in $PSBoundParameters.GetEnumerator()) {'
        '        if ($kvpair.Value -ne $null) {'
        '            $AddNewRow = New-UDRow -Columns {'
        '                New-UDColumn -Size 6 {'
        '                    # Create New Grid'
        '                    [System.Collections.ArrayList]$LastFivePings = @()'
        '                    $PingResultProperties = @("Status","IPAddress","RoundtripTime","DateTime")'
        '                    $PingGrid = New-UdGrid -Title $kvpair.Value -Headers $PingResultProperties -AutoRefresh -Properties $PingResultProperties -Endpoint {'
        '                        try {'
        '                            $ResultPrep =  [System.Net.NetworkInformation.Ping]::new().Send('
        '                                $($kvpair.Value),1000'
        '                            )| Select-Object -Property Address,Status,RoundtripTime -ExcludeProperty PSComputerName,PSShowComputerName,RunspaceId'
        '                            $GridData = [PSCustomObject]@{'
        '                                 IPAddress       = $ResultPrep.Address.IPAddressToString'
        '                                 Status          = $ResultPrep.Status.ToString()'
        '                                 RoundtripTime   = $ResultPrep.RoundtripTime'
        '                                 DateTime        = Get-Date -Format MM-dd-yy_hh:mm:sstt'
        '                            }'
        '                        }'
        '                        catch {'
        '                            $GridData = [PSCustomObject]@{'
        '                                IPAddress       = "Unknown"'
        '                                Status          = "Unknown"'
        '                                RoundtripTime   = "Unknown"'
        '                                DateTime        = Get-Date -Format MM-dd-yy_hh:mm:sstt'
        '                            }'
        '                        }'
        '                        if ($LastFivePings.Count -eq 5) {'
        '                            $LastFivePings.RemoveAt($LastFivePings.Count-1)'
        '                        }'
        '                        $LastFivePings.Insert(0,$GridData)'
        '                        $LastFivePings | Out-UDGridData'
        '                    }'
        '                    $PingGrid'
        '                    #$null = $SubmitButtonActions.Add($PingGrid)'
        '                }'
        ''
        '                New-UDColumn -Size 6 {'
        '                    # Create New Monitor'
        '                    $PingMonitor = New-UdMonitor -Title $kvpair.Value -Type Line -DataPointHistory 20 -RefreshInterval 5 -ChartBackgroundColor "#80FF6B63" -ChartBorderColor "#FFFF6B63"  -Endpoint {'
        '                        try {'
        '                            [bool]$([System.Net.NetworkInformation.Ping]::new().Send($($kvpair.Value),1000)) | Out-UDMonitorData'
        '                        }'
        '                        catch {'
        '                            $False | Out-UDMonitorData'
        '                        }'
        '                    }'
        '                    $PingMonitor'
        '                    #$null = $SubmitButtonActions.Add($PingMonitor)'
        '                }'
        '            }'
        '            $null = $SubmitButtonActions.Add($AddNewRow)'
        '        }'
        '    }'
        'New-UDInputAction -Content $SubmitButtonActions'
    )
    $NMEndPointSBAsString = $NMEndPointSBAsStringPrep -join "`n"
    $NMEndPointSB = [scriptblock]::Create($NMEndPointSBAsString)
    $NetworkMonitorPageContent = {
        New-UDInput -Title "Select Servers To Monitor" -Id "Form" -Content $NMContentSB -Endpoint $NMEndPointSB
    }
    $NetworkMonitorPage = New-UDPage -Name "NetworkMonitor" -Icon dashboard -Content $NetworkMonitorPageContent
    $null = $Pages.Add($NetworkMonitorPage)
    
    # Finalize the Site
    $MyDashboard = New-UDDashboard -Pages $Pages

    # Start the Site
    Start-UDDashboard -Dashboard $MyDashboard -Port $Port
}


[System.Collections.ArrayList]$script:FunctionsForSBUse = @(
    ${Function:GetComputerObjectsInLDAP}.Ast.Extent.Text
    ${Function:GetDomainController}.Ast.Extent.Text
    ${Function:GetElevation}.Ast.Extent.Text
    ${Function:GetGroupObjectsInLDAP}.Ast.Extent.Text
    ${Function:GetModuleDependencies}.Ast.Extent.Text
    ${Function:GetNativePath}.Ast.Extent.Text
    ${Function:GetUserObjectsInLDAP}.Ast.Extent.Text
    ${Function:InvokeModuleDependencies}.Ast.Extent.Text
    ${Function:InvokePSCompatibility}.Ast.Extent.Text
    ${Function:ManualPSGalleryModuleInstall}.Ast.Extent.Text
    ${Function:NewUniqueString}.Ast.Extent.Text
    ${Function:ResolveHost}.Ast.Extent.Text
    ${Function:TestIsValidIPAddress}.Ast.Extent.Text
    ${Function:TestLDAP}.Ast.Extent.Text
    ${Function:TestPort}.Ast.Extent.Text
    ${Function:Get-UDNetMon}.Ast.Extent.Text
)

# SIG # Begin signature block
# MIIMiAYJKoZIhvcNAQcCoIIMeTCCDHUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUZVp9QMMzBAHGVqlPZwdkU6vc
# e3qgggn9MIIEJjCCAw6gAwIBAgITawAAAB/Nnq77QGja+wAAAAAAHzANBgkqhkiG
# 9w0BAQsFADAwMQwwCgYDVQQGEwNMQUIxDTALBgNVBAoTBFpFUk8xETAPBgNVBAMT
# CFplcm9EQzAxMB4XDTE3MDkyMDIxMDM1OFoXDTE5MDkyMDIxMTM1OFowPTETMBEG
# CgmSJomT8ixkARkWA0xBQjEUMBIGCgmSJomT8ixkARkWBFpFUk8xEDAOBgNVBAMT
# B1plcm9TQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDCwqv+ROc1
# bpJmKx+8rPUUfT3kPSUYeDxY8GXU2RrWcL5TSZ6AVJsvNpj+7d94OEmPZate7h4d
# gJnhCSyh2/3v0BHBdgPzLcveLpxPiSWpTnqSWlLUW2NMFRRojZRscdA+e+9QotOB
# aZmnLDrlePQe5W7S1CxbVu+W0H5/ukte5h6gsKa0ktNJ6X9nOPiGBMn1LcZV/Ksl
# lUyuTc7KKYydYjbSSv2rQ4qmZCQHqxyNWVub1IiEP7ClqCYqeCdsTtfw4Y3WKxDI
# JaPmWzlHNs0nkEjvnAJhsRdLFbvY5C2KJIenxR0gA79U8Xd6+cZanrBUNbUC8GCN
# wYkYp4A4Jx+9AgMBAAGjggEqMIIBJjASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsG
# AQQBgjcVAgQWBBQ/0jsn2LS8aZiDw0omqt9+KWpj3DAdBgNVHQ4EFgQUicLX4r2C
# Kn0Zf5NYut8n7bkyhf4wGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDgYDVR0P
# AQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUdpW6phL2RQNF
# 7AZBgQV4tgr7OE0wMQYDVR0fBCowKDAmoCSgIoYgaHR0cDovL3BraS9jZXJ0ZGF0
# YS9aZXJvREMwMS5jcmwwPAYIKwYBBQUHAQEEMDAuMCwGCCsGAQUFBzAChiBodHRw
# Oi8vcGtpL2NlcnRkYXRhL1plcm9EQzAxLmNydDANBgkqhkiG9w0BAQsFAAOCAQEA
# tyX7aHk8vUM2WTQKINtrHKJJi29HaxhPaHrNZ0c32H70YZoFFaryM0GMowEaDbj0
# a3ShBuQWfW7bD7Z4DmNc5Q6cp7JeDKSZHwe5JWFGrl7DlSFSab/+a0GQgtG05dXW
# YVQsrwgfTDRXkmpLQxvSxAbxKiGrnuS+kaYmzRVDYWSZHwHFNgxeZ/La9/8FdCir
# MXdJEAGzG+9TwO9JvJSyoGTzu7n93IQp6QteRlaYVemd5/fYqBhtskk1zDiv9edk
# mHHpRWf9Xo94ZPEy7BqmDuixm4LdmmzIcFWqGGMo51hvzz0EaE8K5HuNvNaUB/hq
# MTOIB5145K8bFOoKHO4LkTCCBc8wggS3oAMCAQICE1gAAAH5oOvjAv3166MAAQAA
# AfkwDQYJKoZIhvcNAQELBQAwPTETMBEGCgmSJomT8ixkARkWA0xBQjEUMBIGCgmS
# JomT8ixkARkWBFpFUk8xEDAOBgNVBAMTB1plcm9TQ0EwHhcNMTcwOTIwMjE0MTIy
# WhcNMTkwOTIwMjExMzU4WjBpMQswCQYDVQQGEwJVUzELMAkGA1UECBMCUEExFTAT
# BgNVBAcTDFBoaWxhZGVscGhpYTEVMBMGA1UEChMMRGlNYWdnaW8gSW5jMQswCQYD
# VQQLEwJJVDESMBAGA1UEAxMJWmVyb0NvZGUyMIIBIjANBgkqhkiG9w0BAQEFAAOC
# AQ8AMIIBCgKCAQEAxX0+4yas6xfiaNVVVZJB2aRK+gS3iEMLx8wMF3kLJYLJyR+l
# rcGF/x3gMxcvkKJQouLuChjh2+i7Ra1aO37ch3X3KDMZIoWrSzbbvqdBlwax7Gsm
# BdLH9HZimSMCVgux0IfkClvnOlrc7Wpv1jqgvseRku5YKnNm1JD+91JDp/hBWRxR
# 3Qg2OR667FJd1Q/5FWwAdrzoQbFUuvAyeVl7TNW0n1XUHRgq9+ZYawb+fxl1ruTj
# 3MoktaLVzFKWqeHPKvgUTTnXvEbLh9RzX1eApZfTJmnUjBcl1tCQbSzLYkfJlJO6
# eRUHZwojUK+TkidfklU2SpgvyJm2DhCtssFWiQIDAQABo4ICmjCCApYwDgYDVR0P
# AQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBS5d2bhatXq
# eUDFo9KltQWHthbPKzAfBgNVHSMEGDAWgBSJwtfivYIqfRl/k1i63yftuTKF/jCB
# 6QYDVR0fBIHhMIHeMIHboIHYoIHVhoGubGRhcDovLy9DTj1aZXJvU0NBKDEpLENO
# PVplcm9TQ0EsQ049Q0RQLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNl
# cnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9emVybyxEQz1sYWI/Y2VydGlmaWNh
# dGVSZXZvY2F0aW9uTGlzdD9iYXNlP29iamVjdENsYXNzPWNSTERpc3RyaWJ1dGlv
# blBvaW50hiJodHRwOi8vcGtpL2NlcnRkYXRhL1plcm9TQ0EoMSkuY3JsMIHmBggr
# BgEFBQcBAQSB2TCB1jCBowYIKwYBBQUHMAKGgZZsZGFwOi8vL0NOPVplcm9TQ0Es
# Q049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENO
# PUNvbmZpZ3VyYXRpb24sREM9emVybyxEQz1sYWI/Y0FDZXJ0aWZpY2F0ZT9iYXNl
# P29iamVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwLgYIKwYBBQUHMAKG
# Imh0dHA6Ly9wa2kvY2VydGRhdGEvWmVyb1NDQSgxKS5jcnQwPQYJKwYBBAGCNxUH
# BDAwLgYmKwYBBAGCNxUIg7j0P4Sb8nmD8Y84g7C3MobRzXiBJ6HzzB+P2VUCAWQC
# AQUwGwYJKwYBBAGCNxUKBA4wDDAKBggrBgEFBQcDAzANBgkqhkiG9w0BAQsFAAOC
# AQEAszRRF+YTPhd9UbkJZy/pZQIqTjpXLpbhxWzs1ECTwtIbJPiI4dhAVAjrzkGj
# DyXYWmpnNsyk19qE82AX75G9FLESfHbtesUXnrhbnsov4/D/qmXk/1KD9CE0lQHF
# Lu2DvOsdf2mp2pjdeBgKMRuy4cZ0VCc/myO7uy7dq0CvVdXRsQC6Fqtr7yob9NbE
# OdUYDBAGrt5ZAkw5YeL8H9E3JLGXtE7ir3ksT6Ki1mont2epJfHkO5JkmOI6XVtg
# anuOGbo62885BOiXLu5+H2Fg+8ueTP40zFhfLh3e3Kj6Lm/NdovqqTBAsk04tFW9
# Hp4gWfVc0gTDwok3rHOrfIY35TGCAfUwggHxAgEBMFQwPTETMBEGCgmSJomT8ixk
# ARkWA0xBQjEUMBIGCgmSJomT8ixkARkWBFpFUk8xEDAOBgNVBAMTB1plcm9TQ0EC
# E1gAAAH5oOvjAv3166MAAQAAAfkwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwx
# CjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGC
# NwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPLYnFJv3vdneb+Q
# Dj5JNnsm1F0IMA0GCSqGSIb3DQEBAQUABIIBAL2OP1hjutXWnpAEFQAB1g1strtf
# TXLhtyi8DSCgHKH/zUmRsTCI5kGBhGTbFqtYTgSN76MCSsDLR7vPV+ndWT1PYNA3
# AU0NBCVtq6KEl3pVNGaPtBjLE/JkgXmVTxaBEgFjLDIOFNqZowyo7oiHTCDm7hQq
# LxE6e6LSEoNoeaoDrXRiLX64cbp1L3KqjngRIbMU33eiqQC4eh3kMT8aS6GIbqoM
# TqIcyqQ0YqJJyKmZrc17WfKUaACW6JQvxJLFI9ujbMMmDRyzzJxB78J5sLLvOrhH
# Gc0FOpmBrcFK3idK8ONVctn8YnGZ328unXtsgVeP7Wx4G5aQTXxVH9y1o2k=
# SIG # End signature block

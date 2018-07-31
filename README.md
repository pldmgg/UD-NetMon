[![Build status](https://ci.appveyor.com/api/projects/status/github/pldmgg/ud-netmon?branch=master&svg=true)](https://ci.appveyor.com/project/pldmgg/ud-netmon/branch/master)


# UD-NetMon
Web-based GUI (PowerShell Universal Dashboard) that pings specified Remote Hosts on your Domain every 5 seconds.

# Screenshots

![Home](/Media/1Home.png)
![HostSelect](/Media/2ServerSelection.png)
![Monitor](/Media/3Monitor.png)

## Getting Started

```powershell
# One time setup
    # Download the repository
    # Unblock the zip
    # Extract the UD-NetMon folder to a module path (e.g. $env:USERPROFILE\Documents\WindowsPowerShell\Modules\)
# Or, with PowerShell 5 or later or PowerShellGet:
    Install-Module UD-NetMon

# Import the module.
    Import-Module UD-NetMon    # Alternatively, Import-Module <PathToModuleFolder>

# Get commands in the module
    Get-Command -Module UD-NetMon

# Get help
    Get-Help <UD-NetMon Function> -Full
    Get-Help about_UD-NetMon
```

## Examples

### Scenario 1: No Parameters

```powershell
PS C:\Users\zeroadmin> Get-UDNetMon

Name        Port Running
----        ---- -------
Dashboard0   80    True

```

- Navigate to `http://localhost`
- Click 'Network Monitor'
- Select the Remote Hosts you want to monitor and click 'Submit'.

### Scenario 2: Different Port

```powershell
PS C:\Users\zeroadmin> Get-UDNetMon -Port 8888

Name        Port   Running
----        ------ -------
Dashboard1   8888    True

```

- Navigate to `http://localhost:8888`
- Click 'Network Monitor'
- Select the Remote Hosts you want to monitor and click 'Submit'.

## Notes

* PSGallery: https://www.powershellgallery.com/packages/ud-netmon

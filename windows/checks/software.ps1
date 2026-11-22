# Software inventory: what the previous owner left behind (saved for review, not judged).
Section 'Software inventory'
$uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object DisplayName |
    Export-Csv (Join-Path $OutDir 'installed_software.csv') -NoTypeInformation
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User |
    Export-Csv (Join-Path $OutDir 'startup_items.csv') -NoTypeInformation
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
    Select-Object TaskPath, TaskName, State, Author | Export-Csv (Join-Path $OutDir 'scheduled_tasks_nonms.csv') -NoTypeInformation
Add-Result 'INFO' 'Software inventory' 'installed_software.csv, startup_items.csv, scheduled_tasks_nonms.csv. Look for anything not from the laptop maker, Microsoft, Intel, AMD or NVIDIA'

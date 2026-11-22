# msinfo32: Windows' own full system report, saved next to the rest.
Section 'msinfo32'
Write-Host 'Writing msinfo32 report (takes about a minute)...'
Start-Process -FilePath msinfo32.exe -ArgumentList "/report `"$(Join-Path $OutDir 'msinfo32.txt')`"" -Wait

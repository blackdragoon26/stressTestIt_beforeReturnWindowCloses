# Event logs: hardware errors, crashes and unexpected shutdowns over the last -EventDays days,
# which covers the time before you had the laptop.
Section "Event logs (last $EventDays days)"
Test-EventLogs -Since (Get-Date).AddDays(-$EventDays)

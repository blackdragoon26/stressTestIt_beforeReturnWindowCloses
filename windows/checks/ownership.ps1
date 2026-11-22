# Ownership: is a company still managing it? Azure AD or domain join, MDM enrollment, local admins.
Section 'Ownership'
$dsreg = dsregcmd /status 2>&1
Save-Text 'dsregcmd.txt' $dsreg
$joined = $dsreg | Select-String -Pattern '^\s*(AzureAdJoined|DomainJoined|EnterpriseJoined)\s*:\s*YES'
if ($joined) { Add-Result 'FAIL' 'Org join' (($joined | ForEach-Object { $_.Line.Trim() }) -join '; ') }
else { Add-Result 'PASS' 'Org join' 'not joined to Azure AD, a domain or an enterprise' }

# Every Windows install has built-in enrollment entries (seen on the ASUS: Deploy, Cloud and Local
# Authority). A real company enrollment (Intune and others) has a user (UPN) or another provider.
$builtin = 'Deploy Authority', 'Cloud Authority', 'Local Authority'
$allEnroll = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
    Where-Object { $_.ProviderID -or $_.UPN })
Save-Text 'mdm_enrollments.txt' ($allEnroll | Select-Object PSChildName, ProviderID, UPN, EnrollmentType | Format-Table -AutoSize | Out-String)
$enroll = @($allEnroll | Where-Object { $_.UPN -or ($builtin -notcontains "$($_.ProviderID)") })
if ($enroll.Count -gt 0) { Add-Result 'FAIL' 'MDM enrollment' (($enroll | ForEach-Object { "$($_.ProviderID) $($_.UPN)" }) -join '; ') }
else { Add-Result 'PASS' 'MDM enrollment' 'none' }

$admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue)
Save-Text 'local_users.txt' ((Get-LocalUser | Format-Table Name, Enabled, LastLogon -AutoSize | Out-String) + "`nAdministrators:`n" + ($admins | Format-Table Name, ObjectClass, PrincipalSource -AutoSize | Out-String))
Add-Result 'INFO' 'Local admins' (($admins.Name) -join ', ')

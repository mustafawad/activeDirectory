Write-Host "Run this script on each Domain Controller" -ForegroundColor Green

# Prompt the user to enter a folder path
$path = Read-Host "Enter the folder path to save reports (e.g., C:\temp)"

# Ensure the folder exists
if (-not (Test-Path $path)) {
    New-Item -ItemType Directory -Path $path | Out-Null
}

$DCName = $env:COMPUTERNAME

# Run DCDiag
$rawOutput = dcdiag /c /v
$AllLines = $rawOutput
$problemLines = $rawOutput | Where-Object { $_ -match 'fail|error|warning' }

# Problem events
$Problemevents = $problemLines | ForEach-Object {
    [PSCustomObject]@{
        Timestamp = (Get-Date)
        Event     = $_
    }
}

# All events
$events = $AllLines | ForEach-Object {
    [PSCustomObject]@{
        Timestamp = (Get-Date)
        Event     = $_
    }
}

# Export problem and all events
$Problemevents | Export-Csv (Join-Path $path "$DCName-Errors.csv") -NoTypeInformation
$events        | Export-Csv (Join-Path $path "$DCName-AllEvents.csv") -NoTypeInformation

# GPO Replication Health
$GPORepHealth = dcdiag /test:frssysvol
$events | Export-Csv (Join-Path $path "$DCName-GPORepHealth.csv") -NoTypeInformation

# AD Replication Error Results
Get-ADReplicationPartnerMetadata -Scope Site -Target * |
    Select-Object Server, Partner, LastReplicationSuccess, LastReplicationResult |
    Export-Csv (Join-Path $path "$DCName-ADReplication.csv") -NoTypeInformation

# Replication reports
repadmin /replsummary > (Join-Path $path "$DCName-replsummary.txt")
repadmin /showrepl *  > (Join-Path $path "$DCName-showrepl.txt")

# SYSVOL Replication
dcdiag /test:frssysvol > (Join-Path $path "$DCName-sysvol.txt")

# NTDS Database Size
$ntdsPath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters")."DSA Database file"
$ntdsSize = (Get-Item $ntdsPath).Length / 1MB
"NTDS.dit Size: {0:N2} MB" -f $ntdsSize | Out-File (Join-Path $path "$DCName-NTDSDatabaseSize.txt")

# DNS Health
dcdiag /test:DNS /v /s:$env:COMPUTERNAME > (Join-Path $path "$DCName-DNSHealth.txt")

# DNS resolving Status
Resolve-DnsName -Name (Get-ADDomain).DNSRoot | Out-File (Join-Path $path "$DCName-DNSResolvingStatus.txt")

# DNS Service Status
Get-Service -Name DNS | Select-Object Name, Status, StartType | Out-File (Join-Path $path "$DCName-DNSServiceStatus.txt")

# DNS Database Info
Get-ChildItem "C:\Windows\System32\dns" -Recurse -Include *.dns |
    Select-Object * |
    Export-Csv (Join-Path $path "$DCName-DNSDatabaseInfo.csv") -NoTypeInformation

# DNS Event Logs
Get-WinEvent -LogName "DNS Server" |
    Where-Object { $_.LevelDisplayName -in "Error", "Warning" } |
    Select-Object TimeCreated, Id, LevelDisplayName, Message |
    Export-Csv (Join-Path $path "$DCName-DNSEvents.csv") -NoTypeInformation

# DNS Zone Health
Get-DnsServerZone | Select-Object * | Export-Csv (Join-Path $path "$DCName-DNSZoneHealth.csv") -NoTypeInformation

# Validate DNS Records
Resolve-DnsName "_ldap._tcp.dc._msdcs.$((Get-ADDomain).DNSRoot)" -Type SRV |
    Out-File (Join-Path $path "$DCName-ValidateDNSRecordsExist.txt")

Write-Host "Report saved to $path" -ForegroundColor Cyan

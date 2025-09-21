Write-Host "Run this script on each Domain Controller" -ForegroundColor Green

# Prompt the user to enter the file path
$path = Read-Host "Enter the full path (including filename) to save the ipconfig result (e.g., C:\temp\FolderName.txt)"

$DCName=hostname

$rawOutput = dcdiag /c /v
$AllLines = $rawOutput
$problemLines = $rawOutput | Where-Object { $_ -match 'fail|error|warning' }

# Format as objects (each row will be one event)
$Problemevents = $problemLines | ForEach-Object {
    [PSCustomObject]@{
        Timestamp = (Get-Date)
        Event     = $_
    }
}

# Format as objects (each row will be one event)
$events = $AllLines | ForEach-Object {
    [PSCustomObject]@{
        Timestamp = (Get-Date)
        Event     = $_
    }
}

# Export to Excel
$Problemevents | export-csv $path\$DCName+Errors.csv
$events | export-csv $path\$DCName+AllEvents.csv

# Check domain-wide GPO replication health
$GPORepHealth = dcdiag /test:frssysvol
$events | export-csv $path\$DCName+GPORepHealth.csv


# Export AD Replication Error Results
Get-ADReplicationPartnerMetadata -Scope Site -Target * |
Select-Object Server, Partner, LastReplicationSuccess, LastReplicationResult |
export-csv $path\$DCName+ADReplication.csv

# Summary View of Replication Health
repadmin /replsummary > $path\$DCName+replsummary.txt

# Detailed View of Replication per Domain Controller
repadmin /showrepl * >  $path\$DCName+showrepl.txt

# Check SYSVOL Replication
dcdiag /test:frssysvol >  $path\$DCName+sysvol.txt

# Check NTDS Database Size
$ntdsPath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters")."DSA Database file"
$ntdsSize = (Get-Item $ntdsPath).Length / 1MB
"NTDS.dit Size: {0:N2} MB" -f $ntdsSize > $path\$DCName+NTDSDatabaseSize.txt

# Check DNS Health
dcdiag /test:DNS /v /s:$env:COMPUTERNAME > $path\$DCName+DNSHealth.txt

# Check DNS resolving Status
Resolve-DnsName -Name (Get-ADDomain).DNSRoot > $path\$DCName+DNSResolvingStatus.txt

# Check DNS Service Status
Get-Service -Name DNS | Select-Object Name, Status, StartType > $path\$DCName+DNSServiceStatus.txt

# Check DNS Database File Size
Get-ChildItem "C:\Windows\System32\dns" -Recurse -Include *.dns | Select-Object * | export-csv $path\$DCName+DNSDatabaseInfo.csv 

# Check DNS Event Logs for Errors or Warnings
Get-WinEvent -LogName "DNS Server" | Where-Object { $_.LevelDisplayName -in "Error", "Warning" } | Select-Object TimeCreated, Id, LevelDisplayName, Message | export-csv $path\$DCName+DNSEvents.csv 

# Check DNS Zone Health
Get-DnsServerZone | Select-Object * | export-csv $path\$DCName+DNSZoneHealth.csv 

# Validate DNS Records Exist for AD
Resolve-DnsName "_ldap._tcp.dc._msdcs.$((Get-ADDomain).DNSRoot)" -Type SRV > $path\$DCName+ValidateDNSRecordsExist.txt 

Write-Host "Report saved to $path" -ForegroundColor Cyan
param(
    [Parameter(Mandatory = $true)]
    [string]$DomainFqdn,

    [Parameter(Mandatory = $true)]
    [string[]]$DomainControllerIps
)

$ports = @(53, 88, 135, 389, 445, 464, 636, 3268, 3269)

Write-Host "Checking domain controller discovery for $DomainFqdn"
nltest /dsgetdc:$DomainFqdn

Write-Host "`nChecking AD DNS service record resolution"
Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainFqdn" -ErrorAction Continue

foreach ($dc in $DomainControllerIps) {
    Write-Host "`nTesting connectivity to domain controller $dc"
    foreach ($port in $ports) {
        $result = Test-NetConnection -ComputerName $dc -Port $port -InformationLevel Quiet
        $status = if ($result) { "REACHABLE" } else { "blocked" }
        Write-Host ("Port {0}: {1}" -f $port, $status)
    }
}

Write-Host "`nExpected drill sandbox result: domain discovery fails and AD ports are blocked."

#DNS Update Script version 1.5

$ip = (Get-NetAdapter -Name "Ethernet 2" | Get-NetIPAddress | Where-Object { $_.AddressFamily -eq 'IPv4' }).IPAddress
$firstOctet = $ip.split(".")[0]
$secondOctet = $ip.split(".")[1]
$thirdOctet = $ip.split(".")[2]

$dnsip = "$firstOctet.$secondOctet.$thirdOctet.100"
$index = Get-NetAdapter -Name 'Ethernet*' | Select-Object -ExpandProperty 'ifIndex'
Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses $dnsip

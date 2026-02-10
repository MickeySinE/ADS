Write-Host "DHCP Windows"

if ((Get-WindowsFeature DHCP).InstallState -ne "Installed") {
    Write-Host "Instalando rol DHCP" 
    Install-WindowsFeature DHCP -IncludeManagementTools
}


function Validar-IP($ip) {
    return $ip -match "^\d{1,3}(\.\d{1,3}){3}$"
}

do {
    $IP_1 = Read-Host "IP inicial (ej. 192.168.100.50)"
} until (Validar-IP $IP_1)

do {
    $IP_2 = Read-Host "IP final (ej. 192.168.100.150)"
} until (Validar-IP $IP_2)

$scope = Read-Host "Nombre del Scope"
$GW = "192.168.100.1"
$DNS = "8.8.8.8" 

try {
    Add-DhcpServerv4Scope -Name $scope -StartRange $IP_1 -EndRange $IP_2 -SubnetMask 255.255.255.0 -State Active
    Set-DhcpServerv4OptionValue -Router $GW -DnsServer $DNS
    Write-Host "Configuración completada" 
} catch {
    Write-Host "El Scope ya existe o hubo un error: $($_.Exception.Message)" 
}

Write-Host "`n==== Estado del Servicio ===="
Get-Service dhcpserver | Select-Object Status, Name

Write-Host "==== Concesiones (Leases) Activas ===="
Get-DhcpServerv4Lease -ScopeId (Get-DhcpServerv4Scope).ScopeId

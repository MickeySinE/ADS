function Log-Exito { param([string]$texto); Write-Host " [OK] $texto" -ForegroundColor Green }
function Log-Error { param([string]$texto); Write-Host " [ERROR] $texto" -ForegroundColor Red }
function Log-Aviso { param([string]$texto); Write-Host " [INFO] $texto" -ForegroundColor Cyan }

function Verificar-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log-Error "Ejecuta como ADMINISTRADOR."; Start-Sleep -Seconds 5; exit
    }
}

function Pedir-Entero {
    param ([string]$Mensaje)
    while ($true) {
        $num = Read-Host "$Mensaje"
        if ($num -match '^\d+$' -and [int]$num -gt 0) { return [int]$num }
        Log-Error "Ingresa un numero entero positivo."
    }
}

function Obtener-Mascara-Desde-Prefijo {
    param ([int]$Prefijo)
    switch ($Prefijo) {
        8  { return "255.0.0.0" }
        16 { return "255.255.0.0" }
        24 { return "255.255.255.0" }
        Default {
            $mascara = [uint32]::MaxValue -shl (32 - $Prefijo)
            $bytes = [BitConverter]::GetBytes([uint32][IPAddress]::HostToNetworkOrder($mascara))
            return (($bytes | ForEach-Object { $_ }) -join ".")
        }
    }
}

function Pedir-IP-Segura {
    param ([string]$Mensaje, [string]$EsOpcional = "no")
    while ($true) {
        $entrada = (Read-Host "$Mensaje").Trim()
        if ($EsOpcional -eq "si" -and $entrada -eq "") { return "" }
        if ($entrada -match '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            if ($entrada -in @("0.0.0.0", "127.0.0.1", "255.255.255.255")) { Log-Error "IP Reservada." }
            else { return $entrada }
        } else { Log-Error "Formato IP invalido." }
    }
}

function Instalar-Rol-DHCP {
    if (-not (Get-WindowsFeature DHCP).Installed) {
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    }
    netsh dhcp add securitygroups | Out-Null
    try {
        $ipServidor = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" } | Select-Object -First 1).IPAddress
        Add-DhcpServerInDC -DnsName $env:COMPUTERNAME -IPAddress $ipServidor -ErrorAction SilentlyContinue
    } catch {}
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\ServicingStorage\ServerComponentCache\DHCP" -Name "InstallState" -Value 1 -ErrorAction SilentlyContinue
    Start-Service DhcpServer -ErrorAction SilentlyContinue
    Log-Exito "DHCP Listo."
    Read-Host "..."
}

function Configurar-Todo-Scope {
    if ((Get-Service DhcpServer).Status -ne "Running") { Log-Error "DHCP no corre."; return }
    
    Get-NetAdapter | Select-Object Name, Status | Format-Table
    $NombreInterfaz = Read-Host "Interfaz [Ethernet 2]"
    if ($NombreInterfaz -eq "") { $NombreInterfaz = "Ethernet 2" }
    
    $RangoInicio = Pedir-IP-Segura "IP Inicio"
    $RangoFin = Pedir-IP-Segura "IP Fin"
    $IPServidor = Pedir-IP-Segura "IP Estatica Servidor"
    $Prefijo = Read-Host "Prefijo [24]"
    if ($Prefijo -eq "") { $Prefijo = 24 }
    $Mascara = Obtener-Mascara-Desde-Prefijo ([int]$Prefijo)
    $Gateway = Pedir-IP-Segura "Gateway (Opcional)" "si"
    $DnsSecundario = Pedir-IP-Segura "DNS Secundario (Opcional)" "si"
    $NombreScope = Read-Host "Nombre del Scope"
    $TiempoLease = Pedir-Entero "Lease (segundos)"

    try {
        Remove-NetIPAddress -InterfaceAlias $NombreInterfaz -Confirm:$false -ErrorAction SilentlyContinue
        $params = @{ InterfaceAlias=$NombreInterfaz; IPAddress=$IPServidor; PrefixLength=$Prefijo }
        if ($Gateway) { $params.DefaultGateway = $Gateway }
        New-NetIPAddress @params -ErrorAction SilentlyContinue
        
        $dnsList = if ($DnsSecundario) { @($IPServidor, $DnsSecundario) } else { @($IPServidor) }
        Set-DnsClientServerAddress -InterfaceAlias $NombreInterfaz -ServerAddresses $dnsList
        
        $octetos = $RangoInicio.Split('.')
        $netID = "$($octetos[0]).$($octetos[1]).$($octetos[2]).0"
        if (Get-DhcpServerv4Scope -ScopeId $netID -ErrorAction SilentlyContinue) { Remove-DhcpServerv4Scope -ScopeId $netID -Force }
        
        Add-DhcpServerv4Scope -Name $NombreScope -StartRange $RangoInicio -EndRange $RangoFin -SubnetMask $Mascara -State Active
        Set-DhcpServerv4Scope -ScopeId $netID -LeaseDuration (New-TimeSpan -Seconds $TiempoLease)
        if ($Gateway) { Set-DhcpServerv4OptionValue -ScopeId $netID -OptionId 3 -Value $Gateway }
        Set-DhcpServerv4OptionValue -ScopeId $netID -OptionId 6 -Value $dnsList -Force
        Add-DhcpServerv4ExclusionRange -ScopeId $netID -StartRange $IPServidor -EndRange $IPServidor -ErrorAction SilentlyContinue
        
        Restart-Service DhcpServer -Force
        Log-Exito "Configuracion Completa."
    } catch { Log-Error "Fallo: $_" }
    Read-Host "..."
}

function Monitorear-Clientes {
    Get-DhcpServerv4Scope | ForEach-Object {
        Write-Host "`n Scope: $($_.ScopeId)" -ForegroundColor Yellow
        Get-DhcpServerv4Lease -ScopeId $_.ScopeId | Select-Object IPAddress, HostName | Format-Table
    }
    Read-Host "..."
}

function Instalar-DNS {
    Install-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null
    Start-Service DNS -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "DNS-UDP" -Direction Inbound -Protocol UDP -LocalPort 53 -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "DNS-TCP" -Direction Inbound -Protocol TCP -LocalPort 53 -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Set-DnsServerSetting -ListeningIPAddress @("0.0.0.0") -ErrorAction SilentlyContinue
    Log-Exito "DNS Operativo."
    Read-Host "..."
}

function Agregar-Dominio-DNS {
    $dominio = Read-Host "Dominio"
    if (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue) { Log-Aviso "Ya existe."; return }
    $ip = Pedir-IP-Segura "IP Dominio"
    Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns"
    Add-DnsServerResourceRecordA -Name "@" -ZoneName $dominio -IPv4Address $ip
    Add-DnsServerResourceRecordA -Name "ns1" -ZoneName $dominio -IPv4Address $ip
    Add-DnsServerResourceRecordCName -Name "www" -HostNameAlias "$dominio." -ZoneName $dominio
    Log-Exito "Agregado."
    Read-Host "..."
}

function Eliminar-Dominio-DNS {
    Get-DnsServerZone | Where-Object { !$_.IsAutoCreated } | ForEach-Object { Write-Host " - $($_.ZoneName)" }
    $dominio = Read-Host "Dominio a borrar"
    if (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $dominio -Force
        Log-Exito "Eliminado."
    }
    Read-Host "..."
}

function Listar-Dominios-DNS {
    Get-DnsServerZone | Where-Object { !$_.IsAutoCreated } | ForEach-Object {
        $ip = (Get-DnsServerResourceRecord -ZoneName $_.ZoneName -RRType A | Where-Object { $_.HostName -eq "@" }).RecordData.IPv4Address
        Write-Host "  $($_.ZoneName) -> $ip"
    }
    Read-Host "..."
}

function Verificar-Estado-Servicio {
    Clear-Host
    Write-Host " STATUS REPORT " -BackgroundColor White -ForegroundColor Black
    foreach ($s in @("DhcpServer", "DNS")) {
        $status = Get-Service $s -ErrorAction SilentlyContinue
        $color = if ($status.Status -eq "Running") { "Green" } else { "Red" }
        Write-Host " >> $s : $($status.Status)" -ForegroundColor $color
    }
    Read-Host "..."
}

function SubMenu-DHCP {
    while ($true) {
        Clear-Host
        Write-Host " [ DHCP MODULE ] " -NoNewline -BackgroundColor Cyan -ForegroundColor Black; Write-Host ""
        Write-Host "  1. Install`n  2. Configure Scope`n  3. Leases`n  4. Remove`n  5. Back"
        switch (Read-Host " Option") {
            "1" { Instalar-Rol-DHCP }
            "2" { Configurar-Todo-Scope }
            "3" { Monitorear-Clientes }
            "4" { if ((Read-Host "Uninstall? (y/n)") -eq "y") { Uninstall-WindowsFeature DHCP } }
            "5" { return }
        }
    }
}

function SubMenu-DNS {
    while ($true) {
        Clear-Host
        Write-Host " [ DNS MODULE ] " -NoNewline -BackgroundColor DarkGreen -ForegroundColor White; Write-Host ""
        Write-Host "  1. Install`n  2. Add Zone`n  3. List Zones`n  4. Delete Zone`n  5. Remove`n  6. Back"
        switch (Read-Host " Option") {
            "1" { Instalar-DNS }
            "2" { Agregar-Dominio-DNS }
            "3" { Listar-Dominios-DNS }
            "4" { Eliminar-Dominio-DNS }
            "5" { if ((Read-Host "Uninstall? (y/n)") -eq "y") { Uninstall-WindowsFeature DNS -Remove } }
            "6" { return }
        }
    }
}

Verificar-Admin
while ($true) {
    Clear-Host
    Write-Host "-----  NET MANAGER SERVER  -----" -ForegroundColor Cyan
    Write-Host "  [1] DHCP Management"
    Write-Host "  [2] DNS Management"
    Write-Host "  [3] System Status"
    Write-Host "  [4] Exit"
    switch (Read-Host "`n Selection") {
        "1" { SubMenu-DHCP }
        "2" { SubMenu-DNS }
        "3" { Verificar-Estado-Servicio }
        "4" { exit }
    }
}

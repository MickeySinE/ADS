function Validar-IP ($ip) {
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255") { return $false }
    return $ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
}

function Menu-DHCP {
    Clear-Host
    Write-Host " ----- DHCP WINDOWS -----" -ForegroundColor Cyan
    Write-Host "[1] Verificar/Instalar DHCP"
    Write-Host "[2] Configurar Nuevo DHCP"
    Write-Host "[3] Monitorear Estado y Leases"
    Write-Host "[4] Salir"
    return Read-Host "`nSeleccione una opcion"
}

do {
    $opcion = Menu-DHCP
    switch ($opcion) {
        "1" {
            if ((Get-WindowsFeature DHCP).InstallState -ne "Installed") {
                Write-Host "Instalando..." -ForegroundColor Yellow
                Install-WindowsFeature DHCP -IncludeManagementTools
            } else { Write-Host "DHCP ya esta instalado" -ForegroundColor Green }
            Pause
        }
        "2" {
            $scope = Read-Host "Nombre del Scope"
            do { $IP1 = Read-Host "IP Inicial" } until (Validar-IP $IP1)
            do { 
                $IP2 = Read-Host "IP Final" 
                $ip1Obj = [ipaddress]$IP1
                $ip2Obj = [ipaddress]$IP2
                $valido = (Validar-IP $IP2) -and ($ip2Obj.Address -gt $ip1Obj.Address)
                if (-not $valido) { Write-Host "Error: IP invalida o menor a la inicial" -ForegroundColor Red }
            } until ($valido)

            $GW = Read-Host "Gateway"
            $DNS = Read-Host "DNS IP"
            
            try {
                Add-DhcpServerv4Scope -Name $scope -StartRange $IP1 -EndRange $IP2 -SubnetMask 255.255.255.0 -State Active
                Set-DhcpServerv4OptionValue -Router $GW -DnsServer $DNS -Force
                Write-Host "Ambito creado con exito." -ForegroundColor Green
            } catch { Write-Host "Error al crear: $($_.Exception.Message)" -ForegroundColor Red }
            Pause
        }
        "3" {
            Write-Host "`n--- Estado del Servicio ---" -ForegroundColor Cyan
            Get-Service dhcpserver | Select-Object Status, Name | Out-String | Write-Host
            
            Write-Host "--- Leases Activos ---" -ForegroundColor Yellow
            $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if ($scopes) {
                foreach ($s in $scopes) {
                    # CORRECCION: Se cambio -DarkGray (error) por -ForegroundColor Gray
                    Write-Host "Ambito: $($s.ScopeId) ($($s.Name))" -ForegroundColor Gray
                    $leases = Get-DhcpServerv4Lease -ScopeId $s.ScopeId -ErrorAction SilentlyContinue
                    if ($leases) { $leases | Out-String | Write-Host } 
                    else { Write-Host "   No hay clientes conectados aun." -ForegroundColor DarkYellow }
                }
            } else {
                Write-Host "No se encontraron ambitos configurados." -ForegroundColor Red
            }
            
            Write-Host "`nPresione Entrar para continuar..."
            Read-Host
        }
    }
} while ($opcion -ne "4")

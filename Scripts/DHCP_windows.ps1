function Validar-IP ($ip) {
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255") { return $false }
    return $ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
}

function Menu-DHCP {
    Clear-Host
    Write-Host " ----- DHCP WINDOWS -----" -ForegroundColor Cyan
    Write-Host "[1] Verificar si DHCP esta instalado"
    Write-Host "[2] Instalar Rol de DHCP"
    Write-Host "[3] Configurar Nuevo DHCP (Auto-reserva de primera IP)"
    Write-Host "[4] Monitorear Estado y Leases"
    Write-Host "[5] Salir"
    return Read-Host "`nSeleccione una opcion"
}

do {
    $opcion = Menu-DHCP
    switch ($opcion) {
        "1" {
            $status = Get-WindowsFeature DHCP
            if ($status.InstallState -eq "Installed") {
                Write-Host "Estado: El rol de DHCP ya esta instalado correctamente." -ForegroundColor Green
            } else {
                Write-Host "Estado: El rol de DHCP NO esta instalado." -ForegroundColor Red
            }
            Pause
        }
        "2" {
            Write-Host "Iniciando instalacion de DHCP..." -ForegroundColor Yellow
            Install-WindowsFeature DHCP -IncludeManagementTools
            Write-Host "Instalacion completada." -ForegroundColor Green
            Pause
        }
        "3" {
            $scope = Read-Host "Nombre del Scope"
            

            do { $IP1 = Read-Host "IP Inicial del segmento (Ej: 192.168.1.0)" } until (Validar-IP $IP1)
            

            $ipPartes = $IP1.Split('.')
            $ultimoOcteto = [int]$ipPartes[3]

            $IP_Gateway = $IP1
            $IP_Inicio_Cliente = "$($ipPartes[0]).$($ipPartes[1]).$($ipPartes[2]).$($ultimoOcteto + 1)"
            
            Write-Host "La IP $IP_Gateway sera usada para el Gateway/Server." -ForegroundColor Cyan
            Write-Host "El rango de clientes empezara desde: $IP_Inicio_Cliente" -ForegroundColor Gray

            do { 
                $IP2 = Read-Host "IP Final del segmento" 
                $ipInicioObj = [ipaddress]$IP_Inicio_Cliente
                $ipFinalObj = [ipaddress]$IP2
                
                $valido = (Validar-IP $IP2) -and ($ipFinalObj.Address -gt $ipInicioObj.Address)
                
                if (-not $valido) { 
                    Write-Host "Error: La IP final debe ser valida y mayor a $IP_Inicio_Cliente" -ForegroundColor Red 
                }
            } until ($valido)

            $DNS = Read-Host "DNS IP"
            
            try {
                Add-DhcpServerv4Scope -Name $scope -StartRange $IP_Inicio_Cliente -EndRange $IP2 -SubnetMask 255.255.255.0 -State Active
                Set-DhcpServerv4OptionValue -Router $IP_Gateway -DnsServer $DNS -Force
                Write-Host "Exito! Ambito creado. Rango clientes: $IP_Inicio_Cliente - $IP2" -ForegroundColor Green
            } catch { 
                Write-Host "Error al crear: $($_.Exception.Message)" -ForegroundColor Red 
            }
            Pause
        }
        "4" {
            Write-Host "`n--- Estado del Servicio ---" -ForegroundColor Cyan
            Get-Service dhcpserver -ErrorAction SilentlyContinue | Select-Object Status, Name | Out-String | Write-Host
            
            Write-Host "--- Leases Activos ---" -ForegroundColor Yellow
            $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if ($scopes) {
                foreach ($s in $scopes) {
                    Write-Host "Ambito: $($s.ScopeId) ($($s.Name))" -ForegroundColor Gray
                    $leases = Get-DhcpServerv4Lease -ScopeId $s.ScopeId -ErrorAction SilentlyContinue
                    if ($leases) { $leases | Out-String | Write-Host } 
                    else { Write-Host "    No hay clientes conectados aun." -ForegroundColor DarkYellow }
                }
            } else { Write-Host "No hay ambitos configurados." -ForegroundColor Red }
            
            Read-Host "`nPresione Entrar para volver al menu..."
        }
    }
} while ($opcion -ne "5")

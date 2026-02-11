function Validar-IP ($ip) {
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255" -or $ip -eq "127.0.0.1") { return $false }
    return $ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
}

function Menu-DHCP {
    Clear-Host
    Write-Host " ----- DHCP WINDOWS -----" -ForegroundColor Cyan
    Write-Host "[1] Verificar si DHCP esta instalado"
    Write-Host "[2] Instalar Rol de DHCP"
    Write-Host "[3] Desinstalar Rol de DHCP (Limpieza)"
    Write-Host "[4] Configurar Nuevo DHCP (Auto-reserva de primera IP)"
    Write-Host "[5] Monitorear Estado y Leases"
    Write-Host "[6] Salir"
    return Read-Host "`nSeleccione una opcion"
}

do {
    $opcion = Menu-DHCP
    switch ($opcion) {
        "1" {
            $status = Get-WindowsFeature DHCP
            if ($status.InstallState -eq "Installed") {
                Write-Host "Estado: El rol de DHCP ya esta instalado." -ForegroundColor Green
            } else {
                Write-Host "Estado: El rol de DHCP NO esta instalado." -ForegroundColor Red
            }
            Pause
        }
        "2" {
            Write-Host "Instalando DHCP..." -ForegroundColor Yellow
            Install-WindowsFeature DHCP -IncludeManagementTools
            Write-Host "Instalacion completada." -ForegroundColor Green
            Pause
        }
        "3" {
            Write-Host "Eliminando Rol de DHCP..." -ForegroundColor Yellow
            Uninstall-WindowsFeature DHCP -IncludeManagementTools
            Write-Host "Rol eliminado. Se recomienda reiniciar para limpiar residuos." -ForegroundColor Cyan
            Pause
        }
        "4" {
            $scope = Read-Host "Nombre del Scope"
            
            do { 
                $IP1 = Read-Host "IP Inicial del segmento (Ej: 192.168.1.0)" 
                if ($IP1 -eq "127.0.0.1") { Write-Host "Error: No puedes usar localhost (127.0.0.1)" -ForegroundColor Red }
            } until ( (Validar-IP $IP1) -and ($IP1 -ne "127.0.0.1") )
            
            $ipPartes = $IP1.Split('.')
            $ultimoOcteto = [int]$ipPartes[3]
            $IP_Gateway = $IP1
            $IP_Inicio_Cliente = "$($ipPartes[0]).$($ipPartes[1]).$($ipPartes[2]).$($ultimoOcteto + 1)"
            
            Write-Host "Gateway reservado: $IP_Gateway" -ForegroundColor Cyan

            do { 
                $IP2 = Read-Host "IP Final del segmento" 
                $ipInicioObj = [ipaddress]$IP_Inicio_Cliente
                $ipFinalObj = [ipaddress]$IP2
                $valido = (Validar-IP $IP2) -and ($ipFinalObj.Address -gt $ipInicioObj.Address)
                if (-not $valido) { Write-Host "Error: IP invalida o menor a $IP_Inicio_Cliente" -ForegroundColor Red }
            } until ($valido)

            do {
                $leaseInput = Read-Host "Tiempo de concesion (Lease Time) en SEGUNDOS"
                if ($leaseInput -match "^\d+$" -and [int]$leaseInput -gt 0) {
                    $leaseValido = $true
                    # Convertir segundos a formato Timespan (Dias.Horas:Minutos:Segundos)
                    $leaseTime = [TimeSpan]::FromSeconds([int]$leaseInput)
                } else {
                    Write-Host "Error: Ingresa un numero entero positivo." -ForegroundColor Red
                    $leaseValido = $false
                }
            } until ($leaseValido)

            $DNS = Read-Host "IP de DNS (Opcional, presiona Enter para saltar)"
            
            try {
                Add-DhcpServerv4Scope -Name $scope -StartRange $IP_Inicio_Cliente -EndRange $IP2 -SubnetMask 255.255.255.0 -State Active -LeaseDuration $leaseTime
                Set-DhcpServerv4OptionValue -Router $IP_Gateway -Force
                
                if ($DNS -and (Validar-IP $DNS)) {
                    Set-DhcpServerv4OptionValue -DnsServer $DNS -Force
                    Write-Host "DNS configurado: $DNS" -ForegroundColor Gray
                }

                Write-Host "Ambito creado con exito!" -ForegroundColor Green
                Write-Host "Clientes desde: $IP_Inicio_Cliente hasta $IP2" -ForegroundColor Gray
            } catch { 
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red 
            }
            Pause
        }
        "5" {
            Write-Host "`n--- Monitoreo ---" -ForegroundColor Cyan
            Get-Service dhcpserver -ErrorAction SilentlyContinue | Select-Object Status, Name
            $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if ($scopes) {
                foreach ($s in $scopes) {
                    Write-Host "Ambito: $($s.ScopeId) - $($s.Name)" -ForegroundColor Yellow
                    Get-DhcpServerv4Lease -ScopeId $s.ScopeId -ErrorAction SilentlyContinue | Out-String | Write-Host
                }
            } else { Write-Host "No hay configuraciones activas." -ForegroundColor Red }
            Pause
        }
    }
} while ($opcion -ne "6")

function Validar-IP ($ip) {
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255" -or $ip -eq "127.0.0.1") { return $false }
    return $ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
}

function Menu-DHCP {
    Clear-Host
    Write-Host " ----- DHCP WINDOWS -----" -ForegroundColor Cyan
    Write-Host "[1] Verificar si DHCP esta instalado"
    Write-Host "[2] Instalar/Desinstalar Rol (Con Validacion)"
    Write-Host "[3] Configurar Nuevo Ambito + IP Estatica Server"
    Write-Host "[4] Monitorear TODOS los Leases Activos"
    Write-Host "[5] Salir"
    return Read-Host "`nSeleccione una opcion"
}

do {
    $opcion = Menu-DHCP
    switch ($opcion) {
        "1" {
            $status = Get-WindowsFeature DHCP
            Write-Host "Estado: $($status.InstallState)" -ForegroundColor Yellow
            Pause
        }
        "2" {
            $status = Get-WindowsFeature DHCP
            $accion = Read-Host "Escribe 'I' para Instalar o 'D' para Desinstalar"
            
            if ($accion -eq 'I') {
                if ($status.InstallState -eq "Installed") {
                    $confirmar = Read-Host "El rol DHCP ya esta instalado. ¿Deseas reinstalarlo? (S/N)"
                    if ($confirmar -eq 'S' -or $confirmar -eq 's') {
                        Write-Host "Reinstalando..." -ForegroundColor Gray
                        Uninstall-WindowsFeature DHCP -IncludeManagementTools
                        Install-WindowsFeature DHCP -IncludeManagementTools
                    } else { Write-Host "Operacion cancelada." -ForegroundColor Yellow }
                } else { Install-WindowsFeature DHCP -IncludeManagementTools }
            }
            elseif ($accion -eq 'D') { Uninstall-WindowsFeature DHCP -IncludeManagementTools }
            Pause
        }
        "3" {
            if ((Get-WindowsFeature DHCP).InstallState -ne "Installed") {
                Write-Host "Error: El rol no esta instalado." -ForegroundColor Red
                Pause ; break
            }
            
            $nombre = Read-Host "Nombre del Ambito"
            do { $IP1 = Read-Host "IP Inicial" } until (Validar-IP $IP1)
            
            $partes = $IP1.Split('.')
            $primerOcteto = [int]$partes[0]
            if ($primerOcteto -ge 1 -and $primerOcteto -le 126) {
                $mascara = "255.0.0.0" ; $prefix = 8
            }
            elseif ($primerOcteto -ge 128 -and $primerOcteto -le 191) {
                $mascara = "255.255.0.0" ; $prefix = 16
            }
            elseif ($primerOcteto -ge 192 -and $primerOcteto -le 223) {
                $mascara = "255.255.255.0" ; $prefix = 24
            }

            Write-Host "Configurando..." -ForegroundColor Cyan
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
            if ($adapter) {
                $adapter | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                $adapter | New-NetIPAddress -IPAddress $IP1 -PrefixLength $prefix -ErrorAction SilentlyContinue | Out-Null
                Write-Host "OK: Servidor configurado con $IP1" -ForegroundColor Green
            }

            $IP_Cliente_Inicio = "$($partes[0]).$($partes[1]).$($partes[2]).$([int]$partes[3] + 1)"
            do { 
                $IP2 = Read-Host "IP Final del rango para clientes"
                $valido = (Validar-IP $IP2)
            } until ($valido)

            $sec = Read-Host "Lease Time (segundos): "
            $dns = Read-Host "DNS (Enter para saltar)"

            try {
                Add-DhcpServerv4Scope -Name $nombre -StartRange $IP_Cliente_Inicio -EndRange $IP2 -SubnetMask $mascara -LeaseDuration ([TimeSpan]::FromSeconds($sec)) | Out-Null
                Set-DhcpServerv4OptionValue -Router $IP1 -Force | Out-Null
                if ($dns) { Set-DhcpServerv4OptionValue -DnsServer $dns -Force | Out-Null }
                
                Write-Host "n¡Exito! Ambito creado y activo." -ForegroundColor Green
            } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
            Pause
        }
        "4" {
            if ((Get-WindowsFeature DHCP).InstallState -eq "Installed") {
                Write-Host "`n--- REPORTE DE LEASES ---" -ForegroundColor Cyan
                $ambitos = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
                if ($ambitos) {
                    foreach ($ambito in $ambitos) {
                        Write-Host "`nRed: $($ambito.ScopeId) | Rango: $($ambito.StartRange) - $($ambito.EndRange)" -ForegroundColor Yellow
                        $leases = Get-DhcpServerv4Lease -ScopeId $ambito.ScopeId -ErrorAction SilentlyContinue
                        if ($leases) { $leases | Select-Object IPAddress, HostName, LeaseExpiryTime | Format-Table -AutoSize }
                        else { Write-Host "  Sin clientes activos." -ForegroundColor DarkGray }
                    }
                } else { Write-Host "No hay ambitos." -ForegroundColor Red }
            } else { Write-Host "Instala el rol primero." -ForegroundColor Red }
            Pause
        }
    }
} while ($opcion -ne "5")

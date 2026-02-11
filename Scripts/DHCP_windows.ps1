function Validar-IP ($ip) {
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255" -or $ip -eq "127.0.0.1") { return $false }
    return $ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
}

function Menu-DHCP {
    Clear-Host
    Write-Host " ----- DHCP WINDOWS -----" -ForegroundColor Cyan
    Write-Host "[1] Verificar si DHCP esta instalado"
    Write-Host "[2] Instalar/Desinstalar Rol (Con Validacion)"
    Write-Host "[3] Configurar Nuevo Ambito (Deteccion de Clase)"
    Write-Host "[4] Monitorear TODOS los Leases Activos"
    Write-Host "[5] Reiniciar Servidor"
    Write-Host "[6] Salir"
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
                    } else {
                        Write-Host "Operacion cancelada." -ForegroundColor Yellow
                    }
                } else {
                    Install-WindowsFeature DHCP -IncludeManagementTools
                }
            }
            elseif ($accion -eq 'D') {
                Uninstall-WindowsFeature DHCP -IncludeManagementTools
            }
            Pause
        }
        "3" {
            if ((Get-WindowsFeature DHCP).InstallState -ne "Installed") {
                Write-Host "Error: El rol no esta instalado." -ForegroundColor Red
                Pause ; break
            }
            
            $nombre = Read-Host "Nombre del Ambito"
            do { $IP1 = Read-Host "IP Inicial (Gateway, ej: 10.0.0.1 o 192.168.1.1)" } until (Validar-IP $IP1)
            
            $partes = $IP1.Split('.')
            $primerOcteto = [int]$partes[0]
            
            if ($primerOcteto -ge 1 -and $primerOcteto -le 126) {
                $mascara = "255.0.0.0" ; $redID = "$($partes[0]).0.0.0" ; $clase = "A"
            }
            elseif ($primerOcteto -ge 128 -and $primerOcteto -le 191) {
                $mascara = "255.255.0.0" ; $redID = "$($partes[0]).$($partes[1]).0.0" ; $clase = "B"
            }
            elseif ($primerOcteto -ge 192 -and $primerOcteto -le 223) {
                $mascara = "255.255.255.0" ; $redID = "$($partes[0]).$($partes[1]).$($partes[2]).0" ; $clase = "C"
            }
            else {
                Write-Host "IP fuera de rango comercial." -ForegroundColor Red ; Pause ; break
            }

            $IP_Cliente_Inicio = "$($partes[0]).$($partes[1]).$($partes[2]).$([int]$partes[3] + 1)"
            
            Write-Host "--- Detalles Automaticos ---" -ForegroundColor Gray
            Write-Host "Clase Detectada: $clase | Red: $redID | Mascara: $mascara"

            do { 
                $IP2 = Read-Host "IP Final del rango"
                $valido = (Validar-IP $IP2)
            } until ($valido)

            $sec = Read-Host "Segundos de Lease"
            $dns = Read-Host "DNS (Enter para saltar)"

            try {
                Add-DhcpServerv4Scope -Name $nombre -StartRange $IP_Cliente_Inicio -EndRange $IP2 -SubnetMask $mascara -LeaseDuration ([TimeSpan]::FromSeconds($sec))
                Set-DhcpServerv4OptionValue -Router $IP1 -Force
                if ($dns) { Set-DhcpServerv4OptionValue -DnsServer $dns -Force }
                Write-Host "¡Exito! Ambito creado." -ForegroundColor Green
            } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
            Pause
        }
        "4" {
            if ((Get-WindowsFeature DHCP).InstallState -eq "Installed") {
                Write-Host "`n--- REPORTE GLOBAL DE LEASES ---" -ForegroundColor Cyan
                $ambitos = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
                
                if ($ambitos) {
                    foreach ($ambito in $ambitos) {
                        Write-Host "`nAmbito: $($ambito.ScopeId) ($($ambito.Name))" -ForegroundColor Yellow
                        $leases = Get-DhcpServerv4Lease -ScopeId $ambito.ScopeId -ErrorAction SilentlyContinue
                        
                        if ($leases) {
                            $leases | Select-Object IPAddress, ClientId, HostName, LeaseExpiryTime | Format-Table -AutoSize
                        } else {
                            Write-Host "  No hay clientes conectados en este ambito." -ForegroundColor DarkGray
                        }
                    }
                } else {
                    Write-Host "No se encontraron ambitos configurados." -ForegroundColor Red
                }
            } else {
                Write-Host "Instala el rol primero." -ForegroundColor Red
            }
            Pause
        }
        "5" { Restart-Computer -Force }
    }
} while ($opcion -ne "6")

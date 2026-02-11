function Validar-IP ($ip) {
    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255" -or $ip -eq "127.0.0.1") { return $false }
    return $ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
}

function Menu-DHCP {
    Clear-Host
    Write-Host " -----  DHCP WINDOWS SERVER -----" -ForegroundColor Cyan
    Write-Host "[1] Verificar estado del Rol DHCP"
    Write-Host "[2] Instalar/Desinstalar Rol"
    Write-Host "[3] Configurar Servidor"
    Write-Host "[4] Monitorear Leases"
    Write-Host "[5] Salir"
    return Read-Host "`nSeleccione una opcion"
}

do {
    $opcion = Menu-DHCP
    switch ($opcion) {
        "1" {
            $status = Get-WindowsFeature DHCP
            Write-Host "`nEstado del rol: $($status.InstallState)" -ForegroundColor Yellow
            Pause
        }
        "2" {
            $status = Get-WindowsFeature DHCP
            $accion = Read-Host "Escriba 'I' para Instalar o 'D' para Desinstalar"
            
            if ($accion -eq 'I') {
                if ($status.InstallState -eq "Installed") {
                    Write-Host "El rol ya esta instalado." -ForegroundColor Yellow
                } else { 
                    Write-Host "Instalando DHCP..." -ForegroundColor Gray
                    Install-WindowsFeature DHCP -IncludeManagementTools 
                }
            }
            elseif ($accion -eq 'D') { 
                Write-Host "Desinstalando DHCP..." -ForegroundColor Gray
                Uninstall-WindowsFeature DHCP -IncludeManagementTools 
            }
            Pause
        }
        "3" {
            if ((Get-WindowsFeature DHCP).InstallState -ne "Installed") {
                Write-Host "Error: Primero instale el rol DHCP." -ForegroundColor Red
                Pause ; break
            }
            
            $nombreAmbito = Read-Host "Nombre del nuevo Ambito"
            do { $ipServer = Read-Host "IP Inicial" } until (Validar-IP $ipServer)

            $partes = $ipServer.Split('.')
            $primerOcteto = [int]$partes[0]
            if ($primerOcteto -ge 1 -and $primerOcteto -le 126) { $mascara = "255.0.0.0" ; $prefix = 8 }
            elseif ($primerOcteto -ge 128 -and $primerOcteto -le 191) { $mascara = "255.255.0.0" ; $prefix = 16 }
            elseif ($primerOcteto -ge 192 -and $primerOcteto -le 223) { $mascara = "255.255.255.0" ; $prefix = 24 }

            Write-Host "Configurando interfaz de red..." -ForegroundColor Cyan
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
            if ($adapter) {
                $adapter | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                $adapter | New-NetIPAddress -IPAddress $ipServer -PrefixLength $prefix -ErrorAction SilentlyContinue | Out-Null
                Write-Host "OK: Servidor configurado con IP $ipServer / $prefix" -ForegroundColor Green
            }

            $ipInicio = "$($partes[0]).$($partes[1]).$($partes[2]).$([int]$partes[3] + 1)"
           do { 
                $ipFinal = Read-Host "IP Final"
                $valido = (Validar-IP $ipFinal)
                if ($valido -and $ipFinal -eq $ipInicio) {
                    Write-Host "Error: La IP final no puede ser la misma que la inicial. Debe dejar un intervalo." -ForegroundColor Red
                    $valido = $false  
                }
            } until ($valido)
            $leaseSec = Read-Host "Lease Time (segundos)"
            $gw = Read-Host "IP del Gateway/Router (Enter para saltar)"
            $dns = Read-Host "IP del DNS Server (Enter para saltar)"

            try {
                Add-DhcpServerv4Scope -Name $nombreAmbito -StartRange $ipInicio -EndRange $ipFinal -SubnetMask $mascara -LeaseDuration ([TimeSpan]::FromSeconds($leaseSec)) | Out-Null
                if ($gw) { Set-DhcpServerv4OptionValue -Router $gw -Force | Out-Null }
                if ($dns) { Set-DhcpServerv4OptionValue -DnsServer $dns -Force | Out-Null }
                
                Write-Host "Ambito Configurado" -ForegroundColor Green
            } catch { 
                Write-Host "Error al crear ambito: $($_.Exception.Message)" -ForegroundColor Red 
            }
            Pause
        }
        "4" {
            Write-Host "`n--- DISPOSITIVOS CONECTADOS ---" -ForegroundColor Cyan
            $ambitos = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if ($ambitos) {
                foreach ($a in $ambitos) {
                    Write-Host "Red: $($a.ScopeId)" -ForegroundColor Yellow
                    $leases = Get-DhcpServerv4Lease -ScopeId $a.ScopeId -ErrorAction SilentlyContinue
                    if ($leases) {
                        $leases | Select-Object IPAddress, HostName, LeaseExpiryTime | Format-Table -AutoSize
                    } else {
                        Write-Host "  No hay clientes activos en este ambito." -ForegroundColor DarkGray
                    }
                }
            } else { Write-Host "No hay ambitos configurados." -ForegroundColor Red }
            Pause
        }
    }
} while ($opcion -ne "5")

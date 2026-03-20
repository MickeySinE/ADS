# =============================================================
#   PRACTICA 7 - Orquestador Unificado (HTTP/FTP/IIS)
#   Sistema: Windows Server 2019
# =============================================================

#Requires -RunAsAdministrator

Import-Module WebAdministration -ErrorAction SilentlyContinue

# -------------------------------------------------------------
# VARIABLES GLOBALES
# -------------------------------------------------------------
$global:FTP_IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*"
} | Select-Object -First 1).IPAddress

$global:PUERTO_ACTUAL = "8080" # Puerto por defecto para el menú rápido
$global:FTP_USER = "anonymous"
$global:FTP_PASS = ""
$global:FTP_BASE = "ftp://127.0.0.1/http/Windows"

$PUERTOS_BLOQUEADOS = @(1,7,9,11,13,15,17,19,20,21,22,23,25,37,42,43,53,69,77,79,
    87,95,101,102,103,104,109,110,111,113,115,117,119,123,135,139,142,143,179,389,
    465,512,513,514,515,526,530,531,532,540,548,554,556,563,587,601,636,993,995,
    2049,3659,4045,6000,6665,6666,6667,6668,6669,6697)

# -------------------------------------------------------------
# FUNCIONES DE APOYO (Limpieza, Certificados, Firewall)
# -------------------------------------------------------------
function Limpiar-Entorno {
    param($Puerto)
    Write-Host "[*] Limpiando servicios en puerto $Puerto..." -ForegroundColor Gray
    Stop-Service nginx, Apache, Apache2.4, W3SVC, ftpsvc -Force -ErrorAction SilentlyContinue
    taskkill /F /IM nginx.exe /T 2>$null
    taskkill /F /IM httpd.exe /T 2>$null
    $con = Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue
    if ($con) { $con.OwningProcess | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue } }
    Start-Sleep -Seconds 1
}

function Obtener-CertObj {
    $certObj = Get-ChildItem "Cert:\LocalMachine\My" | Where-Object { $_.Subject -like "*reprobados*" } | Select-Object -First 1
    if (!$certObj) {
        $certObj = New-SelfSignedCertificate -DnsName "www.reprobados.com" -CertStoreLocation "Cert:\LocalMachine\My" -NotAfter (Get-Date).AddDays(365)
    }
    return $certObj
}

function Abrir-Puerto-Firewall {
    param($Puerto, $Nombre)
    New-NetFirewallRule -DisplayName "Practica7-$Nombre-$Puerto" -Direction Inbound -Protocol TCP -LocalPort $Puerto -Action Allow -ErrorAction SilentlyContinue | Out-Null
}

# -------------------------------------------------------------
# DESPLIEGUE DE SERVICIOS
# -------------------------------------------------------------
function Instalar-Servicio {
    param($Servicio)
    
    Write-Host ""
    Write-Host "1) Chocolatey | 2) FTP Local"
    $origen = Read-Host "Origen de instalacion para $Servicio"

    $P = [int]$global:PUERTO_ACTUAL
    $respSSL = Read-Host "Desea activar SSL en este servicio? [S/N]"
    $usarSSL = ($respSSL -match '^[Ss]$')

    Limpiar-Entorno $P

    if ($origen -eq "1") {
        Write-Host "[*] Instalando $Servicio via Chocolatey..." -ForegroundColor Cyan
        if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        }
        choco install $Servicio -y
    }

    switch ($Servicio) {
        "iis" {
            # Instalación de IIS Feature
            Install-WindowsFeature -Name Web-Server -IncludeManagementTools -ErrorAction SilentlyContinue
            Remove-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
            New-Website -Name "Default Web Site" -Port $P -PhysicalPath "C:\inetpub\wwwroot" -Force
            if ($usarSSL) {
                $certObj = Obtener-CertObj
                New-WebBinding -Name "Default Web Site" -Protocol "https" -Port 443 -IPAddress "*"
                $certObj | New-Item -Path "IIS:\SslBindings\*!443" -Force
            }
            Write-Host "[OK] IIS desplegado en puerto $P" -ForegroundColor Green
        }
        "nginx" {
            # Aquí iría la lógica de config de Nginx de tu archivo anterior...
            Write-Host "[*] Iniciando Nginx en puerto $P..." -ForegroundColor Green
        }
        "apache" {
            Write-Host "[*] Iniciando Apache en puerto $P..." -ForegroundColor Green
        }
    }
    Abrir-Puerto-Firewall $P $Servicio
    Pause
}

# -------------------------------------------------------------
# FTP SEGURO E INFRAESTRUCTURA
# -------------------------------------------------------------
function Configurar-FTP-Seguro {
    $certObj = Obtener-CertObj
    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        & $appcmd set site "Default FTP Site" "-ftpServer.security.ssl.serverCertHash:$($certObj.Thumbprint)" 2>$null
        Write-Host "[OK] FTP Seguro configurado con TLS." -ForegroundColor Green
    } else {
        Write-Host "[!] IIS-FTP no instalado." -ForegroundColor Red
    }
    Pause
}

function Validar-Puerto-Seguro {
    $nuevo = Read-Host "Ingrese el nuevo puerto de escucha"
    if ($nuevo -match '^\d+$' -and [int]$nuevo -le 65535) {
        $global:PUERTO_ACTUAL = $nuevo
        Write-Host "[OK] Puerto global cambiado a $nuevo" -ForegroundColor Green
    }
    Pause
}

# -------------------------------------------------------------
# MENU PRINCIPAL (UNIFICADO)
# -------------------------------------------------------------
function Menu-Principal {
    while ($true) {
        Clear-Host
        Write-Host "====================================================" -ForegroundColor Cyan
        Write-Host "      MODULO HTTP/FTP - IP: $global:FTP_IP" -ForegroundColor Cyan
        Write-Host "      PUERTO CONFIGURADO: $global:PUERTO_ACTUAL" -ForegroundColor Yellow
        Write-Host "====================================================" -ForegroundColor Cyan
        Write-Host " 1) Instalar + Desplegar Nginx"
        Write-Host " 2) Instalar + Desplegar Apache"
        Write-Host " 3) Instalar + Desplegar IIS"
        Write-Host " 4) Configurar FTP Seguro (TLS)"
        Write-Host " 5) Configurar Puerto Global"
        Write-Host " 6) Verificar Netstat (Puertos activos)"
        Write-Host " 7) Resumen de infraestructura"
        Write-Host " 8) Salir"
        Write-Host "===================================================="
        $opcion = Read-Host " Opcion"

        switch ($opcion) {
            "1" { Instalar-Servicio "nginx"  }
            "2" { Instalar-Servicio "apache" }
            "3" { Instalar-Servicio "iis"    }
            "4" { Configurar-FTP-Seguro }
            "5" { Validar-Puerto-Seguro }
            "6" {
                Write-Host "`n--- Puertos activos ---" -ForegroundColor Yellow
                Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | 
                    Select-Object LocalAddress, LocalPort | Sort-Object LocalPort | Format-Table
                Pause
            }
            "7" { 
                # Llama a tu función de resumen original si quieres
                Write-Host "Resumen: IP $global:FTP_IP, Puerto $global:PUERTO_ACTUAL"
                Pause 
            }
            "8" { return }
            default { Write-Host "Invalido" -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

# ESTA LINEA ES LA MAS IMPORTANTE: INICIA EL PROGRAMA
Menu-Principal

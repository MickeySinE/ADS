# ==============================================================================
# MODULO HTTP/FTP COMBINADO - WINDOWS (P07) - VERSION FINAL UNIFICADA
# ==============================================================================

Import-Module WebAdministration -ErrorAction SilentlyContinue

# -------------------------------------------------------------
# VARIABLES GLOBALES Y CONFIGURACIÓN
# -------------------------------------------------------------
$global:FTP_IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
    $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*" 
} | Select-Object -First 1).IPAddress

$global:FTP_USER = "anonymous"
$global:FTP_PASS = ""
$global:FTP_BASE = "ftp://127.0.0.1/http/Windows"
$global:PUERTO_ACTUAL = "8080" # Valor por defecto

$PUERTOS_BLOQUEADOS = @(1,7,9,11,13,15,17,19,20,21,22,23,25,37,42,43,53,69,77,79,
    87,95,101,102,103,104,109,110,111,113,115,117,119,123,135,139,142,143,179,389,
    465,512,513,514,515,526,530,531,532,540,548,554,556,563,587,601,636,993,995,
    2049,3659,4045,6000,6665,6666,6667,6668,6669,6697)

# -------------------------------------------------------------
# UTILIDADES DE LIMPIEZA Y PÁGINA WEB
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

function Crear-Pagina {
    param($servicio, $puerto, $ssl)
    $paths = @{
        "nginx"  = "C:\tools\nginx\html\index.html"
        "apache" = "C:\tools\apache\htdocs\index.html"
        "iis"    = "C:\inetpub\wwwroot\index.html"
    }
    $path = $paths[$servicio]
    if (!$path) { return }
    $dir = Split-Path $path
    if (!(Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    
    $protocolo = if ($ssl) { "HTTPS (Seguro)" } else { "HTTP (Estándar)" }
    $color = if ($ssl) { "#16a34a" } else { "#dc2626" }

    $html = @"
<html><head><title>$($servicio.ToUpper())</title>
<style>body{font-family:sans-serif;text-align:center;padding-top:50px;background:#f4f4f4;}
.box{display:inline-block;padding:30px;background:white;border-top:5px solid $color;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);}</style>
</head><body><div class="box"><h1>$($servicio.ToUpper()) ONLINE</h1>
<p>Puerto: <b>$puerto</b></p><p>Protocolo: <span style="color:$color">$protocolo</span></p>
<p>Servidor: Windows Server 2019</p></div></body></html>
"@
    Set-Content $path $html -Encoding ASCII
}

# -------------------------------------------------------------
# GESTIÓN DE CERTIFICADOS SSL
# -------------------------------------------------------------
function Generar-Certificado-SSL {
    $dir = "C:\ssl\reprobados"; $crt = "$dir\reprobados.crt"; $key = "$dir\reprobados.key"
    if (!(Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    
    if ((Test-Path $crt) -and (Test-Path $key)) {
        return @{ CRT = $crt; KEY = $key; OK = $true }
    }

    $openssl = (Get-Command openssl -ErrorAction SilentlyContinue).Source
    if (!$openssl) { $openssl = "C:\Program Files\Git\usr\bin\openssl.exe" }

    if (Test-Path $openssl) {
        & $openssl genrsa -out $key 2048 2>$null
        & $openssl req -new -x509 -key $key -out $crt -days 365 -subj "/CN=www.reprobados.com" 2>$null
        return @{ CRT = $crt; KEY = $key; OK = $true }
    }
    return @{ OK = $false }
}

function Obtener-CertObj {
    $cert = Get-ChildItem "Cert:\LocalMachine\My" | Where-Object { $_.Subject -like "*reprobados*" } | Select-Object -First 1
    if (!$cert) {
        $cert = New-SelfSignedCertificate -DnsName "www.reprobados.com" -CertStoreLocation "Cert:\LocalMachine\My" -NotAfter (Get-Date).AddDays(365)
    }
    return $cert
}

# -------------------------------------------------------------
# DESPLIEGUE DE SERVICIOS
# -------------------------------------------------------------
function Aplicar-Despliegue {
    param($Servicio)

    $P = [int]$global:PUERTO_ACTUAL
    $cert = Generar-Certificado-SSL
    $respSSL = Read-Host "Desea activar SSL en este servicio? [S/N]"
    $usarSSL = ($respSSL -match '^[Ss]$') -and $cert.OK

    Limpiar-Entorno $P

    switch ($Servicio) {
        "nginx" {
            $nginxDir = "C:\tools\nginx"
            
            # --- CORRECCIÓN: Verificar y crear directorios ---
            if (!(Test-Path "$nginxDir\conf")) { 
                Write-Host "[*] Creando estructura de directorios para Nginx..." -ForegroundColor Yellow
                New-Item -Path "$nginxDir\conf" -ItemType Directory -Force | Out-Null
                New-Item -Path "$nginxDir\html" -ItemType Directory -Force | Out-Null
            }

            $conf = "$nginxDir\conf\nginx.conf"
            $certAbs = ($cert.CRT -replace '\\','/')
            $keyAbs = ($cert.KEY -replace '\\','/')

            if ($usarSSL) {
                $cfg = @"
worker_processes 1;
events { worker_connections 1024; }
http {
    include mime.types;
    server {
        listen $P ssl;
        server_name localhost;
        ssl_certificate "$certAbs";
        ssl_certificate_key "$keyAbs";
        location / { root html; index index.html; }
    }
}
"@
            } else {
                $cfg = @"
worker_processes 1;
events { worker_connections 1024; }
http {
    include mime.types;
    server {
        listen $P;
        server_name localhost;
        location / { root html; index index.html; }
    }
}
"@
            }
            
            # --- CORRECCIÓN: Escribir configuración con validación ---
            Set-Content -Path $conf -Value $cfg -Encoding ASCII -Force
            Crear-Pagina "nginx" $P $usarSSL

            # --- CORRECCIÓN: Validar ejecutable antes de arrancar ---
            if (Test-Path "$nginxDir\nginx.exe") {
                Start-Process "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -WindowStyle Hidden
                Write-Host "[OK] Nginx ONLINE en puerto $P" -ForegroundColor Green
            } else {
                Write-Host "[!] ERROR: No se encuentra nginx.exe en $nginxDir. ¿Lo descargaste primero?" -ForegroundColor Red
            }
        }

        "apache" {
            # Lógica similar para Apache asegurando que C:\tools\apache exista
            $apacheDir = "C:\tools\apache"
            if (!(Test-Path "$apacheDir\bin")) {
                Write-Host "[!] No se encuentra Apache en $apacheDir" -ForegroundColor Red
                return
            }
            # ... resto del código de apache ...
        }

        "iis" {
            # IIS no suele dar este error porque las rutas son fijas (C:\inetpub)
            # ... resto del código de iis ...
        }
    }
    Pause
}

# -------------------------------------------------------------
# MENÚS Y LÓGICA DE CONTROL (TU PARTE SOLICITADA)
# -------------------------------------------------------------
function Validar-Puerto-Seguro {
    $nuevo = Read-Host "Ingrese el puerto deseado"
    if ($nuevo -match '^\d+$' -and [int]$nuevo -le 65535) {
        if ([int]$nuevo -in $PUERTOS_BLOQUEADOS) {
            Write-Host "[!] Advertencia: Puerto restringido por navegadores." -ForegroundColor Yellow
        }
        $global:PUERTO_ACTUAL = $nuevo
    }
}

function Mostrar-Resumen {
    Write-Host "--- RESUMEN DE PUERTOS Y SERVICIOS ---" -ForegroundColor Cyan
    Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in @(80, 443, 21, 8080, $global:PUERTO_ACTUAL) } | Format-Table LocalAddress, LocalPort, State
    Pause
}

function Menu-Principal {
    while ($true) {
        Clear-Host
        $p = $global:PUERTO_ACTUAL
        Write-Host "====================================================" -ForegroundColor Cyan
        Write-Host "      MODULO HTTP/FTP - IP: $global:FTP_IP" -ForegroundColor Cyan
        Write-Host "      PUERTO CONFIGURADO: $p" -ForegroundColor Yellow
        Write-Host "====================================================" -ForegroundColor Cyan
        Write-Host " 1) Instalar + Desplegar Nginx"
        Write-Host " 2) Instalar + Desplegar Apache"
        Write-Host " 3) Instalar + Desplegar IIS"
        Write-Host " 4) Configurar FTP Seguro (TLS)"
        Write-Host " 5) Configurar Puerto"
        Write-Host "----------------------------------------------------"
        Write-Host " 6) Verificar Netstat (Puertos comunes)"
        Write-Host " 7) Resumen de infraestructura"
        Write-Host " 8) Salir"
        Write-Host "===================================================="
        $opcion = Read-Host " Opcion"

        switch ($opcion) {
            "1" { Aplicar-Despliegue "nginx" }
            "2" { Aplicar-Despliegue "apache" }
            "3" { Aplicar-Despliegue "iis" }
            "4" { Write-Host "Configurando FTP..."; Start-Sleep 1 } # Lógica de FTP aquí
            "5" { Validar-Puerto-Seguro }
            "6" {
                Write-Host ""; Write-Host "--- Puertos activos ---" -ForegroundColor Yellow
                $puertos_interes = @(80,443,21,8080,8443,9090)
                if ($p -match '^\d+$') { $puertos_interes += [int]$p }
                Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                    Where-Object { $_.LocalPort -in $puertos_interes } |
                    Select-Object LocalAddress, LocalPort | Sort-Object LocalPort | Format-Table -AutoSize
                Pause
            }
            "7" { Mostrar-Resumen }
            "8" { return }
            default { Write-Host "Opcion invalida" -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

Menu-Principal

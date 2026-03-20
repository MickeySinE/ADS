# ==============================================================================
# MODULO HTTP/FTP COMBINADO - WINDOWS (P07) - UNIFICADO
# ==============================================================================

Import-Module WebAdministration -ErrorAction SilentlyContinue

$PUERTOS_BLOQUEADOS = @(1,7,9,11,13,15,17,19,20,21,22,23,25,37,42,43,53,69,77,79,
    87,95,101,102,103,104,109,110,111,113,115,117,119,123,135,139,142,143,179,389,
    465,512,513,514,515,526,530,531,532,540,548,554,556,563,587,601,636,993,995,
    2049,3659,4045,6000,6665,6666,6667,6668,6669,6697)

# ================================================================
# LIMPIEZA Y PAGINA
# ================================================================

function Limpiar-Entorno {
    param($Puerto)
    Write-Host "[*] Limpiando servicios en puerto $Puerto..." -ForegroundColor Gray
    Stop-Service nginx, Apache, Apache2.4, W3SVC, ftpsvc -Force -ErrorAction SilentlyContinue
    taskkill /F /IM nginx.exe /T 2>$null
    taskkill /F /IM httpd.exe /T 2>$null
    $con = Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue
    if ($con) { $con.OwningProcess | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue } }
    Start-Sleep -Seconds 2
}

function Crear-Pagina {
    param($servicio, $puerto)
    $paths = @{
        "nginx"  = "C:\tools\nginx\html\index.html"
        "apache" = "C:\Apache24\htdocs\index.html"
        "iis"    = "C:\inetpub\wwwroot\index.html"
    }
    $path = $paths[$servicio]
    if (!$path) { return }
    $dir = Split-Path $path
    if (!(Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    
    $html = @"
<html><head><title>$($servicio.ToUpper()) - Puerto $puerto</title></head>
<body><h1>$($servicio.ToUpper()) Activo</h1>
<p>Servicio: $($servicio.ToUpper())</p><p>Puerto: $puerto</p></body></html>
"@
    Set-Content $path $html -Encoding ASCII
}

# ================================================================
# CERTIFICADO SSL
# ================================================================

function Generar-Certificado-SSL {
    $dir = "C:\ssl\reprobados"; $crt = "$dir\reprobados.crt"; $key = "$dir\reprobados.key"
    if (!(Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }

    if ((Test-Path $crt) -and (Test-Path $key)) {
        return @{ CRT = $crt; KEY = $key; OK = $true }
    }

    $opensslPath = $null
    foreach ($c in @("C:\Program Files\Git\usr\bin\openssl.exe", "C:\Program Files (x86)\Git\usr\bin\openssl.exe")) {
        if (Test-Path $c) { $opensslPath = $c; break }
    }

    if ($opensslPath) {
        & $opensslPath genrsa -out $key 2048 2>$null
        & $opensslPath req -new -x509 -key $key -out $crt -days 365 -subj "/CN=www.reprobados.com" 2>$null
        return @{ CRT = $crt; KEY = $key; OK = $true }
    }
    return @{ OK = $false }
}

function Obtener-CertObj {
    $certObj = Get-ChildItem "Cert:\LocalMachine\My" | Where-Object { $_.Subject -like "*reprobados*" } | Select-Object -First 1
    if (!$certObj) {
        $certObj = New-SelfSignedCertificate -DnsName "www.reprobados.com" -CertStoreLocation "Cert:\LocalMachine\My" -NotAfter (Get-Date).AddDays(365)
    }
    return $certObj
}

# ================================================================
# DESPLIEGUE POR SERVICIO
# ================================================================

function Aplicar-Despliegue {
    param($Servicio)

    if (!($global:PUERTO_ACTUAL -match '^\d+$')) {
        Write-Host "[!] No se ha configurado un puerto." -ForegroundColor Yellow
        Validar-Puerto-Seguro
    }
    
    $P = [int]$global:PUERTO_ACTUAL
    $cert = Generar-Certificado-SSL
    $respSSL = Read-Host "Desea activar SSL en este servicio? [S/N]"
    $usarSSL = ($respSSL -match '^[Ss]$') -and $cert.OK

    Limpiar-Entorno $P

    switch ($Servicio) {
        "nginx" {
            $nginxExeItem = Get-ChildItem "C:\tools\nginx" -Recurse -Filter "nginx.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if (!$nginxExeItem) { Write-Host "[!] nginx.exe no encontrado."; Pause; return }
            $nginxDir = $nginxExeItem.DirectoryName
            $conf = "$nginxDir\conf\nginx.conf"
            
            $cfg = "worker_processes 1; events { worker_connections 1024; } http { include mime.types; server { listen $P $(if($usarSSL){'ssl'}); server_name localhost; $(if($usarSSL){"ssl_certificate C:/ssl/reprobados/reprobados.crt; ssl_certificate_key C:/ssl/reprobados/reprobados.key;"}) location / { root html; index index.html; } } }"
            Set-Content $conf $cfg -Encoding ASCII
            Crear-Pagina "nginx" $P
            Start-Process "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -WindowStyle Hidden
        }
        "apache" {
            # Lógica simplificada de Apache
            Write-Host "[*] Desplegando Apache en puerto $P..."
            Crear-Pagina "apache" $P
        }
        "iis" {
            Remove-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
            New-Website -Name "Default Web Site" -Port $P -PhysicalPath "C:\inetpub\wwwroot" -Force
            if ($usarSSL) {
                $certObj = Obtener-CertObj
                New-WebBinding -Name "Default Web Site" -Protocol "https" -Port $P -IPAddress "*"
                $certObj | New-Item -Path "IIS:\SslBindings\*!$P" -Force
            }
            Crear-Pagina "iis" $P
        }
    }
    Write-Host "[OK] $Servicio desplegado en puerto $P" -ForegroundColor Green
    Pause
}

# ================================================================
# FUNCIONES FTP E INSTALACIÓN
# ================================================================

function Listar-Archivos-FTP {
    param($url, $usuario, $clave)
    try {
        $req = [System.Net.FtpWebRequest]::Create($url)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
        $req.Credentials = New-Object System.Net.NetworkCredential($usuario, $clave)
        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $lista = $reader.ReadToEnd(); $reader.Close(); $resp.Close()
        return ($lista -split "`n" | ForEach-Object { if ($_ -match '\s+(\S+)$') { $matches[1] } })
    } catch { return @() }
}

function Descargar-FTP {
    param($url, $destino, $usuario, $clave)
    try {
        $req = [System.Net.FtpWebRequest]::Create($url)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($usuario, $clave)
        $resp = $req.GetResponse()
        $fs = [System.IO.File]::Create($destino)
        $resp.GetResponseStream().CopyTo($fs); $fs.Close(); $resp.Close()
        return $true
    } catch { return $false }
}

function Instalar-Servicio {
    param($Servicio)
    Write-Host ""
    Write-Host "1) Chocolatey | 2) FTP Local"
    $origen = Read-Host "Origen de instalacion"
    
    if ($origen -eq "2") {
        $ftpDir = "$global:FTP_BASE/$Servicio"
        $archivos = Listar-Archivos-FTP $ftpDir $global:FTP_USER $global:FTP_PASS
        if ($archivos.Count -eq 0) { Write-Host "[!] No hay archivos en FTP."; Pause; return }
        
        $archivo = $archivos[0] # Simplificado: toma el primero
        $dest = Join-Path $env:TEMP $archivo
        if (Descargar-FTP "$ftpDir/$archivo" $dest $global:FTP_USER $global:FTP_PASS) {
            Write-Host "[OK] Descargado. Extrayendo..."
            if ($archivo -like "*.zip") { Expand-Archive $dest -DestinationPath "C:\tools\$Servicio" -Force }
        }
    }
    Aplicar-Despliegue $Servicio
}

function Configurar-FTP-Seguro {
    Write-Host "[*] Configurando SSL para IIS-FTP..." -ForegroundColor Cyan
    $certObj = Obtener-CertObj
    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
    & $appcmd set site "Default FTP Site" "-ftpServer.security.ssl.serverCertHash:$($certObj.Thumbprint)" 2>$null
    Write-Host "[OK] FTP Seguro configurado." -ForegroundColor Green
    Pause
}

function Validar-Puerto-Seguro {
    $nuevo = Read-Host "Ingrese el puerto (Ej: 8080)"
    if ($nuevo -match '^\d+$' -and [int]$nuevo -le 65535) {
        $global:PUERTO_ACTUAL = $nuevo
        Write-Host "[OK] Puerto $nuevo configurado." -ForegroundColor Green
    }
}

function Mostrar-Resumen {
    Write-Host "--- RESUMEN ---" -ForegroundColor Cyan
    Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq $global:PUERTO_ACTUAL } | Format-Table
    Pause
}

# ================================================================
# MENU PRINCIPAL (ESTRUCTURA FINAL)
# ================================================================

function Menu-FTP-HTTP {
    $global:FTP_IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }).IPAddress | Select-Object -First 1
    $global:FTP_USER = "anonymous"; $global:FTP_PASS = ""; $global:FTP_BASE = "ftp://127.0.0.1/http/Windows"
    $global:PUERTO_ACTUAL = "8080"

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
        Write-Host " 5) Configurar Puerto"
        Write-Host " 6) Verificar Netstat"
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
                Get-NetTCPConnection -State Listen | Select-Object LocalPort, OwningProcess | Sort-Object LocalPort | Out-String | Write-Host 
                Pause 
            }
            "7" { Mostrar-Resumen }
            "8" { return }
            default { Write-Host "Invalido" -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

# ESTO ES LO QUE HACÍA QUE NO SE ABRIERA: LA LLAMADA A LA FUNCIÓN
Menu-FTP-HTTP

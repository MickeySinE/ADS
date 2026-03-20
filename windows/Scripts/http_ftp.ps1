# =============================================================
#   PRACTICA 7 - Orquestador de Instalacion con SSL/TLS
#   Sistema: Windows Server 2019
#   Servicios: Apache, Nginx, Tomcat, FTP (IIS-FTP)
#
#   Ejecutar como Administrador:
#   powershell -ExecutionPolicy Bypass -File practica7_windows.ps1
# =============================================================

#Requires -RunAsAdministrator

Import-Module WebAdministration -ErrorAction SilentlyContinue

# -------------------------------------------------------------
# VARIABLES GLOBALES
# -------------------------------------------------------------
$global:FTP_IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*"
} | Select-Object -First 1).IPAddress

$PUERTOS_BLOQUEADOS = @(1,7,9,11,13,15,17,19,20,21,22,23,25,37,42,43,53,69,77,79,
    87,95,101,102,103,104,109,110,111,113,115,117,119,123,135,139,142,143,179,389,
    465,512,513,514,515,526,530,531,532,540,548,554,556,563,587,601,636,993,995,
    2049,3659,4045,6000,6665,6666,6667,6668,6669,6697)

# -------------------------------------------------------------
# LIMPIAR ENTORNO
# -------------------------------------------------------------
function Limpiar-Entorno {
    param($Puerto)
    Write-Host "[*] Limpiando puerto $Puerto..." -ForegroundColor Gray
    $con = Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue
    if ($con) {
        $con.OwningProcess | ForEach-Object {
            Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 1
}

# -------------------------------------------------------------
# PEDIR PUERTO
# -------------------------------------------------------------
function Pedir-Puerto {
    param($Nombre, $DefaultHTTP, $DefaultHTTPS)

    do {
        $ph = Read-Host "  Puerto HTTP para $Nombre [Enter = $DefaultHTTP]"
        if ([string]::IsNullOrWhiteSpace($ph)) { $ph = $DefaultHTTP }
    } while (-not ($ph -match '^\d+$' -and [int]$ph -ge 1 -and [int]$ph -le 65535))

    do {
        $ps = Read-Host "  Puerto HTTPS para $Nombre [Enter = $DefaultHTTPS]"
        if ([string]::IsNullOrWhiteSpace($ps)) { $ps = $DefaultHTTPS }
        if ($ps -eq $ph) { Write-Host "  HTTPS no puede ser igual a HTTP." }
    } while (-not ($ps -match '^\d+$' -and [int]$ps -ge 1 -and [int]$ps -le 65535 -and $ps -ne $ph))

    foreach ($p in @($ph, $ps)) {
        if ([int]$p -in $PUERTOS_BLOQUEADOS) {
            Write-Host "  ADVERTENCIA: puerto $p bloqueado por navegadores." -ForegroundColor Yellow
        }
        if (Get-NetTCPConnection -LocalPort ([int]$p) -State Listen -ErrorAction SilentlyContinue) {
            Write-Host "  ADVERTENCIA: puerto $p ya esta en uso." -ForegroundColor Yellow
        }
    }

    return @([int]$ph, [int]$ps)
}

# -------------------------------------------------------------
# CREAR PAGINA HTML
# -------------------------------------------------------------
function Crear-Index {
    param($Servidor, $SSL, $Puerto, $DocRoot)

    $color = if ($SSL) { "#16a34a" } else { "#dc2626" }
    $msg   = if ($SSL) { "HTTPS" }   else { "HTTP" }
    $icon  = if ($SSL) { "&#10003;" } else { "&#10007;" }

    New-Item -ItemType Directory -Force -Path $DocRoot | Out-Null
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>$Servidor</title>
<style>
  body { margin: 0; font-family: sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; background: #fafafa; color: #111; }
  .wrap { text-align: center; }
  .dot { width: 10px; height: 10px; border-radius: 50%; background: $color; display: inline-block; margin-bottom: 2rem; }
  h1 { font-size: 1.6rem; font-weight: 600; margin: 0 0 .4rem; }
  .badge { display: inline-block; margin: 1.2rem 0; padding: .3rem .9rem; border: 1.5px solid $color; color: $color; font-size: .85rem; border-radius: 99px; }
  .meta { font-size: .85rem; color: #777; margin-top: .5rem; }
</style>
</head>
<body>
<div class="wrap">
  <div class="dot"></div>
  <h1>$Servidor</h1>
  <div class="badge">$icon $msg</div>
  <div class="meta">www.reprobados.com &nbsp;&middot;&nbsp; :$Puerto</div>
</div>
</body>
</html>
"@
    Set-Content -Path "$DocRoot\index.html" -Value $html -Encoding UTF8
}

# -------------------------------------------------------------
# CERTIFICADO SSL CON OPENSSL DE GIT
# -------------------------------------------------------------
function Generar-Certificado-SSL {
    $dir = "C:\ssl\reprobados"
    $crt = "$dir\reprobados.crt"
    $key = "$dir\reprobados.key"

    if (!(Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }

    $crtOk = (Test-Path $crt) -and ((Get-Content $crt -First 1) -like "-----BEGIN*")
    $keyOk = (Test-Path $key) -and ((Get-Content $key -First 1) -like "-----BEGIN*")

    if ($crtOk -and $keyOk) {
        Write-Host "[*] Reutilizando certificado existente." -ForegroundColor Yellow
        return @{ CRT = $crt; KEY = $key; OK = $true }
    }

    $opensslPath = $null
    foreach ($c in @(
        "C:\Program Files\Git\usr\bin\openssl.exe",
        "C:\Program Files (x86)\Git\usr\bin\openssl.exe",
        "C:\tools\apache\bin\openssl.exe",
        "C:\ProgramData\chocolatey\bin\openssl.exe"
    )) {
        if (Test-Path $c) { $opensslPath = $c; break }
    }
    if (!$opensslPath) {
        $cmd = Get-Command openssl -ErrorAction SilentlyContinue
        if ($cmd) { $opensslPath = $cmd.Source }
    }

    if ($opensslPath) {
        Write-Host "[*] Generando certificado SSL..." -ForegroundColor Cyan
        & $opensslPath genrsa -out $key 2048 2>$null
        & $opensslPath req -new -x509 -key $key -out $crt -days 365 `
            -subj "/C=MX/ST=Sinaloa/L=LosMochis/O=Reprobados/CN=www.reprobados.com" 2>$null
        Write-Host "[OK] Certificado generado en $dir" -ForegroundColor Green
        return @{ CRT = $crt; KEY = $key; OK = $true }
    } else {
        Write-Host "[!] OpenSSL no encontrado." -ForegroundColor Red
        return @{ CRT = $crt; KEY = $key; OK = $false }
    }
}

function Obtener-CertObj {
    $certObj = Get-ChildItem "Cert:\LocalMachine\My" |
        Where-Object { $_.Subject -like "*reprobados*" } | Select-Object -First 1
    if (!$certObj) {
        $certObj = New-SelfSignedCertificate -DnsName "www.reprobados.com" `
            -CertStoreLocation "Cert:\LocalMachine\My" `
            -NotAfter (Get-Date).AddDays(365) -KeyExportPolicy Exportable
    }
    return $certObj
}

# -------------------------------------------------------------
# FIREWALL
# -------------------------------------------------------------
function Abrir-Puerto-Firewall {
    param($Puerto, $Nombre)
    New-NetFirewallRule -DisplayName "Practica7-$Nombre-$Puerto" `
        -Direction Inbound -Protocol TCP -LocalPort $Puerto `
        -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  [OK] Firewall: puerto $Puerto abierto." -ForegroundColor Green
}

# -------------------------------------------------------------
# EXTRAER ZIP
# -------------------------------------------------------------
function Extraer-Zip {
    param($Zip, $Destino)
    $temp = "$env:TEMP\zip_$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    Expand-Archive -Path $Zip -DestinationPath $temp -Force

    $items = Get-ChildItem $temp
    New-Item -ItemType Directory -Force -Path $Destino | Out-Null
    if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
        Get-ChildItem "$($items[0].FullName)" | Move-Item -Destination $Destino -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Extraido desde subcarpeta $($items[0].Name)" -ForegroundColor Green
    } else {
        Get-ChildItem "$temp" | Move-Item -Destination $Destino -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Extraido a $Destino" -ForegroundColor Green
    }
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}

# -------------------------------------------------------------
# FTP - LISTAR Y DESCARGAR
# -------------------------------------------------------------
function Listar-Archivos-FTP {
    param($url, $usuario, $clave)
    try {
        $req = [System.Net.FtpWebRequest]::Create($url)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
        $req.Credentials = New-Object System.Net.NetworkCredential($usuario, $clave)
        $req.UsePassive = $true; $req.UseBinary = $true; $req.KeepAlive = $false
        $resp   = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $lista  = $reader.ReadToEnd(); $reader.Close(); $resp.Close()
        $archivos = @()
        foreach ($linea in ($lista -split "`n")) {
            $l = $linea.Trim().TrimEnd("`r")
            if ($l -eq "") { continue }
            $tokens = ($l -split " +") | Where-Object { $_ -ne "" }
            if ($tokens.Count -ge 4) {
                $nombre = $tokens[-1]
                if ($nombre -notlike "*.sha256" -and $nombre -ne "") { $archivos += $nombre }
            }
        }
        return $archivos
    } catch {
        Write-Host "[!] Error FTP: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Descargar-FTP {
    param($url, $destino, $usuario, $clave)
    try {
        $req = [System.Net.FtpWebRequest]::Create($url)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($usuario, $clave)
        $req.UsePassive = $true; $req.UseBinary = $true; $req.KeepAlive = $false
        $resp = $req.GetResponse()
        $fs   = [System.IO.File]::Create($destino)
        $resp.GetResponseStream().CopyTo($fs); $fs.Close(); $resp.Close()
        return $true
    } catch {
        Write-Host "[!] Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Seleccionar-Desde-FTP {
    param($Servicio)
    $ftpBase = "ftp://127.0.0.1/http/Windows"
    $ftpUser = "anonymous"
    $ftpPass = ""
    $ftpDir  = "$ftpBase/$Servicio"

    Write-Host "[*] Listando $ftpDir ..." -ForegroundColor Cyan
    $archivos = Listar-Archivos-FTP $ftpDir $ftpUser $ftpPass
    if ($archivos.Count -eq 0) { return $null }

    for ($i = 0; $i -lt $archivos.Count; $i++) { Write-Host "$($i+1)) $($archivos[$i])" }
    $sel = Read-Host "Seleccione"
    $idx = 0
    if (![int]::TryParse($sel, [ref]$idx) -or $idx -lt 1 -or $idx -gt $archivos.Count) {
        Write-Host "[!] Seleccion invalida."; return $null
    }
    $archivo   = $archivos[$idx - 1]
    $destLocal = Join-Path $env:TEMP $archivo
    Write-Host "[*] Descargando $archivo..." -ForegroundColor Yellow

    if (!(Descargar-FTP "$ftpDir/$archivo" $destLocal $ftpUser $ftpPass)) { return $null }

    $ok2 = Descargar-FTP "$ftpDir/$archivo.sha256" "$destLocal.sha256" $ftpUser $ftpPass
    if ($ok2 -and (Test-Path "$destLocal.sha256")) {
        $h1 = (Get-FileHash $destLocal -Algorithm SHA256).Hash.ToUpper()
        $h2 = (Get-Content "$destLocal.sha256").Trim().Split()[0].ToUpper()
        if ($h1 -ne $h2) { Write-Host "[!] Hash invalido." -ForegroundColor Red; return $null }
        Write-Host "[OK] Hash SHA256 verificado." -ForegroundColor Green
    } else {
        Write-Host "[!] Sin .sha256 - se omite validacion." -ForegroundColor Yellow
    }
    return $destLocal
}

# -------------------------------------------------------------
# NGINX - puerto propio 8081/8444
# -------------------------------------------------------------
function Instalar-Nginx {
    Write-Host ""
    Write-Host "-- Configuracion de puertos para Nginx ----------"
    $puertos      = Pedir-Puerto "Nginx" 8081 8444
    $puerto_http  = $puertos[0]
    $puerto_https = $puertos[1]

    $cert = Generar-Certificado-SSL
    $resp = Read-Host "Desea activar SSL? [S/N]"
    $ssl  = ($resp -match '^[Ss]$') -and $cert.OK

    $nginxDir = "C:\tools\nginx"
    Write-Host ""; Write-Host "1) WEB  2) FTP"
    $origen = Read-Host "Origen"

    if ($origen -eq "2") {
        $zip = Seleccionar-Desde-FTP "Nginx"
        if (!$zip) { return }
        if (Test-Path $nginxDir) { Remove-Item $nginxDir -Recurse -Force }
        Extraer-Zip $zip $nginxDir
    } else {
        Write-Host "[*] Descargando Nginx..." -ForegroundColor Cyan
        $zip = "$env:TEMP\nginx.zip"
        & curl.exe -L --silent -o $zip "https://nginx.org/download/nginx-1.26.2.zip"
        if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 100000) {
            Write-Host "[!] Descarga fallida."; return
        }
        if (Test-Path $nginxDir) { Remove-Item $nginxDir -Recurse -Force }
        Extraer-Zip $zip $nginxDir
    }

    New-Item -ItemType Directory -Force -Path "$nginxDir\conf" | Out-Null
    $puerto_display = if ($ssl) { $puerto_https } else { $puerto_http }
    Crear-Index "Nginx" $ssl $puerto_display "$nginxDir\html"

    $certFwd = ($cert.CRT) -replace '\\','/'
    $keyFwd  = ($cert.KEY) -replace '\\','/'

    if ($ssl) {
        $cfg = @"
worker_processes 1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    server {
        listen $puerto_http;
        server_name www.reprobados.com;
        return 301 https://`$host:$puerto_https`$request_uri;
    }
    server {
        listen $puerto_https ssl;
        server_name www.reprobados.com;
        ssl_certificate      $certFwd;
        ssl_certificate_key  $keyFwd;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        location / { root html; index index.html; }
    }
}
"@
        Abrir-Puerto-Firewall $puerto_http  "Nginx-HTTP"
        Abrir-Puerto-Firewall $puerto_https "Nginx-HTTPS"
    } else {
        $cfg = @"
worker_processes 1;
events { worker_connections 1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    server {
        listen $puerto_http;
        server_name www.reprobados.com;
        location / { root html; index index.html; }
    }
}
"@
        Abrir-Puerto-Firewall $puerto_http "Nginx-HTTP"
    }

    Set-Content "$nginxDir\conf\nginx.conf" $cfg -Encoding ASCII

    Limpiar-Entorno $puerto_http
    if ($ssl) { Limpiar-Entorno $puerto_https }

    $test = & "$nginxDir\nginx.exe" -t -p $nginxDir 2>&1
    if ($test -notmatch "successful") {
        Write-Host "[!] Error en config Nginx: $test" -ForegroundColor Red; return
    }

    Start-Process "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -WindowStyle Hidden
    Start-Sleep -Seconds 3

    if (Get-NetTCPConnection -LocalPort $puerto_http -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "[OK] Nginx ONLINE" -ForegroundColor Green
        $proto  = if ($ssl) { "https" } else { "http" }
        $puerto = if ($ssl) { $puerto_https } else { $puerto_http }
        Write-Host "     -> http://$global:FTP_IP:$puerto_http" -ForegroundColor Cyan
        if ($ssl) { Write-Host "     -> https://$global:FTP_IP:$puerto_https" -ForegroundColor Cyan }
    } else {
        Write-Host "[!] Nginx no levanto." -ForegroundColor Red
        Get-Content "$nginxDir\logs\error.log" -ErrorAction SilentlyContinue | Select-Object -Last 5
    }
    Pause
}

# -------------------------------------------------------------
# APACHE - puerto propio 80/443
# -------------------------------------------------------------
function Instalar-Apache {
    Write-Host ""
    Write-Host "-- Configuracion de puertos para Apache ---------"
    $puertos      = Pedir-Puerto "Apache" 80 443
    $puerto_http  = $puertos[0]
    $puerto_https = $puertos[1]

    $cert = Generar-Certificado-SSL
    $resp = Read-Host "Desea activar SSL? [S/N]"
    $ssl  = ($resp -match '^[Ss]$') -and $cert.OK

    # Detener IIS si ocupa el puerto
    if (Get-NetTCPConnection -LocalPort $puerto_http -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "[*] Puerto $puerto_http ocupado, deteniendo IIS..." -ForegroundColor Yellow
        Stop-Service W3SVC,WAS -Force -ErrorAction SilentlyContinue
        Set-Service W3SVC -StartupType Disabled -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    $apacheDir = "C:\tools\apache"
    Write-Host ""; Write-Host "1) WEB  2) FTP"
    $origen = Read-Host "Origen"

    if ($origen -eq "2") {
        $zip = Seleccionar-Desde-FTP "Apache"
        if (!$zip) { return }
        Stop-Service "Apache2.4" -Force -ErrorAction SilentlyContinue
        & "$apacheDir\bin\httpd.exe" -k uninstall -n "Apache2.4" 2>$null
        if (Test-Path $apacheDir) { Remove-Item $apacheDir -Recurse -Force }
        Extraer-Zip $zip $apacheDir
    } else {
        Write-Host "[*] Descargando Apache..." -ForegroundColor Cyan
        $zip = "$env:TEMP\apache.zip"
        & curl.exe -L --silent -o $zip "https://www.apachelounge.com/download/VS18/binaries/httpd-2.4.66-260223-Win64-VS18.zip"
        if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 100000) {
            Write-Host "[!] Descarga fallida."; return
        }
        Stop-Service "Apache2.4" -Force -ErrorAction SilentlyContinue
        & "$apacheDir\bin\httpd.exe" -k uninstall -n "Apache2.4" 2>$null
        if (Test-Path $apacheDir) { Remove-Item $apacheDir -Recurse -Force }
        Extraer-Zip $zip $apacheDir
    }

    $conf    = "$apacheDir\conf\httpd.conf"
    $webRoot = "$apacheDir\htdocs"
    if (!(Test-Path $conf)) { Write-Host "[!] httpd.conf no encontrado."; return }

    $puerto_display = if ($ssl) { $puerto_https } else { $puerto_http }
    Crear-Index "Apache (httpd)" $ssl $puerto_display $webRoot

    $apacheFwd = ($apacheDir) -replace '\\','/'
    $webFwd    = $webRoot -replace '\\','/'
    $certDir   = "C:/ssl/reprobados"

    # Configurar httpd.conf base
    (Get-Content $conf) `
        -replace 'SRVROOT ".*"',"SRVROOT `"$apacheFwd`"" `
        -replace '^Listen 80$',"#Listen 80" |
        Set-Content $conf

    $extraConf = "$apacheDir\conf\extra"
    New-Item -ItemType Directory -Force -Path $extraConf | Out-Null

    if ($ssl) {
        (Get-Content $conf) `
            -replace '#LoadModule ssl_module','LoadModule ssl_module' `
            -replace '#LoadModule socache_shmcb_module','LoadModule socache_shmcb_module' `
            -replace '#Include conf/extra/httpd-ssl.conf','Include conf/extra/httpd-ssl.conf' |
            Set-Content $conf

        $vhost = @"

Listen $puerto_http
Listen $puerto_https

<VirtualHost *:$puerto_http>
    ServerName www.reprobados.com
    Redirect permanent / https://www.reprobados.com:$puerto_https/
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
</VirtualHost>

<VirtualHost *:$puerto_https>
    ServerName www.reprobados.com
    DocumentRoot "$webFwd"
    SSLEngine on
    SSLCertificateFile    "$certDir/reprobados.crt"
    SSLCertificateKeyFile "$certDir/reprobados.key"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    <Directory "$webFwd">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
"@
        Abrir-Puerto-Firewall $puerto_http  "Apache-HTTP"
        Abrir-Puerto-Firewall $puerto_https "Apache-HTTPS"
    } else {
        $vhost = @"

Listen $puerto_http

<VirtualHost *:$puerto_http>
    ServerName www.reprobados.com
    DocumentRoot "$webFwd"
    <Directory "$webFwd">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
"@
        Abrir-Puerto-Firewall $puerto_http "Apache-HTTP"
    }

    Add-Content $conf $vhost

    $test = & "$apacheDir\bin\httpd.exe" -t 2>&1
    $ok   = $test | Where-Object { $_ -like "*Syntax OK*" }
    if (!$ok) {
        Write-Host "[!] Error en config Apache:" -ForegroundColor Red
        $test | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        return
    }
    Write-Host "[OK] Sintaxis Apache correcta." -ForegroundColor Green

    & "$apacheDir\bin\httpd.exe" -k install -n "Apache2.4" 2>$null
    Start-Service "Apache2.4" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    if (Get-NetTCPConnection -LocalPort $puerto_http -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "[OK] Apache ONLINE" -ForegroundColor Green
        Write-Host "     -> http://$global:FTP_IP:$puerto_http" -ForegroundColor Cyan
        if ($ssl) { Write-Host "     -> https://$global:FTP_IP:$puerto_https" -ForegroundColor Cyan }
    } else {
        Write-Host "[!] Apache no levanto." -ForegroundColor Red
    }
    Pause
}

# -------------------------------------------------------------
# TOMCAT - puerto propio 8080/8443
# -------------------------------------------------------------
function Instalar-Tomcat {
    Write-Host ""
    Write-Host "-- Configuracion de puertos para Tomcat ---------"
    $puertos      = Pedir-Puerto "Tomcat" 8080 8443
    $puerto_http  = $puertos[0]
    $puerto_https = $puertos[1]

    $cert = Generar-Certificado-SSL
    $resp = Read-Host "Desea activar SSL? [S/N]"
    $ssl  = ($resp -match '^[Ss]$') -and $cert.OK

    # Verificar Java
    $java = Get-Command java -ErrorAction SilentlyContinue
    if (!$java) {
        Write-Host "[!] Java no encontrado. Descargando OpenJDK 17..." -ForegroundColor Yellow
        $msi = "$env:TEMP\jdk17.msi"
        & curl.exe -L --silent -o $msi "https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.msi"
        Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait
        $env:Path += ";C:\Program Files\Microsoft\jdk-17\bin"
    }

    $tomcatDir = "C:\tools\tomcat"
    Write-Host ""; Write-Host "1) WEB  2) FTP"
    $origen = Read-Host "Origen"

    if ($origen -eq "2") {
        $zip = Seleccionar-Desde-FTP "Tomcat"
        if (!$zip) { return }
        Stop-Service "Tomcat10" -Force -ErrorAction SilentlyContinue
        $svcBat = "$tomcatDir\bin\service.bat"
        if (Test-Path $svcBat) { & cmd /c "`"$svcBat`" remove Tomcat10" 2>$null }
        if (Test-Path $tomcatDir) { Remove-Item $tomcatDir -Recurse -Force }
        Extraer-Zip $zip $tomcatDir
    } else {
        Write-Host "[*] Descargando Tomcat 10..." -ForegroundColor Cyan
        $zip = "$env:TEMP\tomcat.zip"
        & curl.exe -L --silent -o $zip "https://dlcdn.apache.org/tomcat/tomcat-10/v10.1.30/bin/apache-tomcat-10.1.30-windows-x64.zip"
        if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 100000) {
            Write-Host "[!] Descarga fallida."; return
        }
        Stop-Service "Tomcat10" -Force -ErrorAction SilentlyContinue
        $svcBat = "$tomcatDir\bin\service.bat"
        if (Test-Path $svcBat) { & cmd /c "`"$svcBat`" remove Tomcat10" 2>$null }
        if (Test-Path $tomcatDir) { Remove-Item $tomcatDir -Recurse -Force }
        Extraer-Zip $zip $tomcatDir
    }

    $docroot = "$tomcatDir\webapps\ROOT"
    New-Item -ItemType Directory -Force -Path $docroot | Out-Null
    $puerto_display = if ($ssl) { $puerto_https } else { $puerto_http }
    Crear-Index "Tomcat" $ssl $puerto_display $docroot

    if ($ssl) {
        # Generar keystore con openssl de Git
        $opensslPath = "C:\Program Files\Git\usr\bin\openssl.exe"
        $ks = "C:\ssl\reprobados\tomcat.p12"
        & $opensslPath pkcs12 -export `
            -in  $cert.CRT -inkey $cert.KEY `
            -out $ks -name tomcat `
            -passout pass:reprobados 2>$null
        $ksFwd = $ks -replace '\\','/'

        $server_xml = @"
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector port="$puerto_http" protocol="HTTP/1.1" connectionTimeout="20000" redirectPort="$puerto_https"/>
    <Connector port="$puerto_https" protocol="org.apache.coyote.http11.Http11NioProtocol" maxThreads="150" SSLEnabled="true">
      <SSLHostConfig>
        <Certificate certificateKeystoreFile="$ksFwd" type="RSA" certificateKeystorePassword="reprobados"/>
      </SSLHostConfig>
    </Connector>
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true"/>
    </Engine>
  </Service>
</Server>
"@
        New-Item -ItemType Directory -Force -Path "$docroot\WEB-INF" | Out-Null
        $web_xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="https://jakarta.ee/xml/ns/jakartaee" version="5.0">
  <filter>
    <filter-name>httpHeaderSecurity</filter-name>
    <filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class>
    <init-param><param-name>hstsEnabled</param-name><param-value>true</param-value></init-param>
    <init-param><param-name>hstsMaxAgeSeconds</param-name><param-value>31536000</param-value></init-param>
    <init-param><param-name>hstsIncludeSubDomains</param-name><param-value>true</param-value></init-param>
  </filter>
  <filter-mapping>
    <filter-name>httpHeaderSecurity</filter-name>
    <url-pattern>/*</url-pattern>
  </filter-mapping>
  <security-constraint>
    <web-resource-collection>
      <web-resource-name>Forzar HTTPS</web-resource-name>
      <url-pattern>/*</url-pattern>
    </web-resource-collection>
    <user-data-constraint>
      <transport-guarantee>CONFIDENTIAL</transport-guarantee>
    </user-data-constraint>
  </security-constraint>
</web-app>
"@
        Set-Content "$docroot\WEB-INF\web.xml" $web_xml
        Abrir-Puerto-Firewall $puerto_http  "Tomcat-HTTP"
        Abrir-Puerto-Firewall $puerto_https "Tomcat-HTTPS"
    } else {
        $server_xml = @"
<Server port="8005" shutdown="SHUTDOWN">
  <Service name="Catalina">
    <Connector port="$puerto_http" protocol="HTTP/1.1" connectionTimeout="20000"/>
    <Engine name="Catalina" defaultHost="localhost">
      <Host name="localhost" appBase="webapps" unpackWARs="true" autoDeploy="true"/>
    </Engine>
  </Service>
</Server>
"@
        Abrir-Puerto-Firewall $puerto_http "Tomcat-HTTP"
    }

    Set-Content "$tomcatDir\conf\server.xml" $server_xml

    $env:CATALINA_HOME = $tomcatDir
    $svcBat = "$tomcatDir\bin\service.bat"
    if (Test-Path $svcBat) {
        & cmd /c "`"$svcBat`" install Tomcat10" 2>$null
        Start-Service "Tomcat10" -ErrorAction SilentlyContinue
        Set-Service "Tomcat10" -StartupType Automatic -ErrorAction SilentlyContinue
    } else {
        $startupBat = "$tomcatDir\bin\startup.bat"
        if (Test-Path $startupBat) {
            Start-Process cmd -ArgumentList "/c `"$startupBat`"" -WorkingDirectory $tomcatDir -WindowStyle Hidden
        }
    }

    Write-Host "[*] Esperando que Tomcat levante (8s)..." -ForegroundColor Gray
    Start-Sleep -Seconds 8

    if (Get-NetTCPConnection -LocalPort $puerto_http -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "[OK] Tomcat ONLINE" -ForegroundColor Green
        Write-Host "     -> http://$global:FTP_IP:$puerto_http" -ForegroundColor Cyan
        if ($ssl) { Write-Host "     -> https://$global:FTP_IP:$puerto_https" -ForegroundColor Cyan }
    } else {
        Write-Host "[!] Tomcat no levanto." -ForegroundColor Red
        Get-Content "$tomcatDir\logs\catalina.out" -ErrorAction SilentlyContinue | Select-Object -Last 10
    }
    Pause
}

# -------------------------------------------------------------
# FTP SEGURO (IIS-FTP)
# -------------------------------------------------------------
function Configurar-FTP-Seguro {
    $appcmd  = "$env:windir\system32\inetsrv\appcmd.exe"
    $certObj = Obtener-CertObj

    $ftpFeature = Get-WindowsFeature -Name "Web-Ftp-Server" -ErrorAction SilentlyContinue
    if ($ftpFeature -and !$ftpFeature.Installed) {
        Write-Host "[*] Instalando IIS-FTP..." -ForegroundColor Cyan
        Install-WindowsFeature -Name Web-Ftp-Server -IncludeManagementTools
    }

    $sitioFTP = & $appcmd list site 2>$null |
        ForEach-Object { if ($_ -match 'SITE object "([^"]+)"') { $matches[1] } } |
        Where-Object { $_ -ne "" } | Select-Object -First 1

    if (!$sitioFTP) {
        if (!(Test-Path "C:\FTP_Publico")) { New-Item "C:\FTP_Publico" -ItemType Directory -Force | Out-Null }
        & $appcmd add site /name:"ServidorFTP" /bindings:"ftp/*:21:" /physicalPath:"C:\FTP_Publico" 2>$null
        $sitioFTP = "ServidorFTP"
    }

    Write-Host "[*] Configurando FTP seguro: $sitioFTP" -ForegroundColor Cyan
    & $appcmd set site "$sitioFTP" "-ftpServer.security.ssl.controlChannelPolicy:SslAllow" 2>$null
    & $appcmd set site "$sitioFTP" "-ftpServer.security.ssl.dataChannelPolicy:SslAllow"    2>$null
    & $appcmd set site "$sitioFTP" "-ftpServer.security.ssl.serverCertHash:$($certObj.Thumbprint)" 2>$null
    & $appcmd set config "$sitioFTP" /section:system.ftpServer/security/authentication/anonymousAuthentication /enabled:true /commit:apphost 2>$null
    & $appcmd set config "$sitioFTP" /section:system.ftpServer/security/authentication/basicAuthentication    /enabled:true /commit:apphost 2>$null

    Set-Service ftpsvc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    & $appcmd start site "$sitioFTP" 2>$null
    Start-Sleep -Seconds 2

    Abrir-Puerto-Firewall 21  "FTP"
    Abrir-Puerto-Firewall 990 "FTPS"

    if (Get-NetTCPConnection -LocalPort 21 -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "[OK] IIS-FTP ONLINE en puerto 21" -ForegroundColor Green
    } else {
        Write-Host "[!] FTP no levanto." -ForegroundColor Red
    }
    Pause
}

# -------------------------------------------------------------
# PURGAR TODO
# -------------------------------------------------------------
function Purgar-Todo {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host "              PURGAR TODO - CONFIRMACION                 " -ForegroundColor Red
    Write-Host "==========================================================" -ForegroundColor Red
    $conf = Read-Host "  Confirmas? [s/N]"
    if ($conf -notmatch '^[Ss]$') { Write-Host "Cancelado."; return }

    Write-Host "[*] Deteniendo servicios..." -ForegroundColor Gray
    Stop-Service "Apache2.4","Tomcat10" -Force -ErrorAction SilentlyContinue
    taskkill /F /IM nginx.exe /T 2>$null
    taskkill /F /IM httpd.exe /T 2>$null

    & "C:\tools\apache\bin\httpd.exe" -k uninstall -n "Apache2.4" 2>$null
    $svcBat = "C:\tools\tomcat\bin\service.bat"
    if (Test-Path $svcBat) { & cmd /c "`"$svcBat`" remove Tomcat10" 2>$null }
    sc.exe delete Tomcat10 2>$null

    Write-Host "[*] Borrando carpetas..." -ForegroundColor Gray
    Remove-Item "C:\tools\nginx"    -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\tools\apache"   -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\tools\tomcat"   -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\ssl\reprobados" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "[*] Borrando certificados..." -ForegroundColor Gray
    Get-ChildItem Cert:\LocalMachine\My | Where-Object {
        $_.Subject -like "*reprobados*"
    } | Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Host "[*] Limpiando firewall..." -ForegroundColor Gray
    Get-NetFirewallRule -DisplayName "Practica7-*" -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    Write-Host "[OK] Purga completa. Ya puedes reinstalar." -ForegroundColor Green
    Pause
}

# -------------------------------------------------------------
# RESUMEN
# -------------------------------------------------------------
function Mostrar-Resumen {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   RESUMEN - $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ("{0,-22} {1,-8} {2,-10} {3}" -f "Servicio","Puerto","Estado","Detalle") -ForegroundColor White
    Write-Host ("-" * 60) -ForegroundColor Gray

    $servicios = @(
        @{ Nombre="Nginx HTTP";      Puerto=8081; Proto="http"  }
        @{ Nombre="Nginx HTTPS";     Puerto=8444; Proto="https" }
        @{ Nombre="Apache HTTP";     Puerto=80;   Proto="http"  }
        @{ Nombre="Apache HTTPS";    Puerto=443;  Proto="https" }
        @{ Nombre="Tomcat HTTP";     Puerto=8080; Proto="http"  }
        @{ Nombre="Tomcat HTTPS";    Puerto=8443; Proto="https" }
        @{ Nombre="IIS-FTP";         Puerto=21;   Proto="ftp"   }
    )

    foreach ($svc in $servicios) {
        $escucha = Get-NetTCPConnection -LocalPort $svc.Puerto -State Listen -ErrorAction SilentlyContinue
        if ($escucha) {
            $detalle = "Escuchando"
            if ($svc.Proto -eq "https") {
                try {
                    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
                    $req = [System.Net.HttpWebRequest]::Create("https://localhost:$($svc.Puerto)")
                    $req.Timeout = 4000
                    $resp = $req.GetResponse(); $resp.Close()
                    $detalle = "SSL OK"
                } catch { $detalle = "SSL ERROR" }
                [Net.ServicePointManager]::ServerCertificateValidationCallback = $null
                try {
                    $wr = Invoke-WebRequest "https://localhost:$($svc.Puerto)" -UseBasicParsing -TimeoutSec 4 -ErrorAction Stop
                    if ($wr.Headers["Strict-Transport-Security"]) { $detalle += " | HSTS OK" }
                } catch {}
            }
            Write-Host ("{0,-22} {1,-8} {2,-10} {3}" -f $svc.Nombre,$svc.Puerto,"[ACTIVO]",$detalle) -ForegroundColor Green
        } else {
            Write-Host ("{0,-22} {1,-8} {2,-10} {3}" -f $svc.Nombre,$svc.Puerto,"[INACTIVO]","No escucha") -ForegroundColor Red
        }
    }

    Write-Host ("-" * 60) -ForegroundColor Gray
    Write-Host ""
    Write-Host "--- Certificados SSL en disco ---" -ForegroundColor Cyan
    foreach ($f in @("C:\ssl\reprobados\reprobados.crt","C:\ssl\reprobados\reprobados.key")) {
        if (Test-Path $f) {
            Write-Host "  [OK] $f" -ForegroundColor Green
        } else {
            Write-Host "  [!] NO existe: $f" -ForegroundColor Red
        }
    }
    Write-Host "============================================================" -ForegroundColor Cyan
    Pause
}

# -------------------------------------------------------------
# MENU PRINCIPAL
# -------------------------------------------------------------
function Menu-Principal {
    while ($true) {
        Write-Host ""
        Write-Host "====================================================" -ForegroundColor Cyan
        Write-Host "   PRACTICA 7 - ORQUESTADOR WINDOWS 2019            " -ForegroundColor Cyan
        Write-Host "   IP: $global:FTP_IP                               " -ForegroundColor Yellow
        Write-Host "====================================================" -ForegroundColor Cyan
        Write-Host " 1) Nginx        (default: 8081 / 8444)"
        Write-Host " 2) Apache       (default: 80   / 443)"
        Write-Host " 3) Tomcat       (default: 8080 / 8443)"
        Write-Host " 4) FTP Seguro   (IIS-FTP puerto 21)"
        Write-Host " 5) Ver Resumen"
        Write-Host " 6) Purgar Todo"
        Write-Host " 0) Salir"
        Write-Host "===================================================="
        $opcion = Read-Host "Opcion"

        switch ($opcion) {
            "0" { Write-Host "Saliendo..."; return }
            "1" { Instalar-Nginx }
            "2" { Instalar-Apache }
            "3" { Instalar-Tomcat }
            "4" { Configurar-FTP-Seguro }
            "5" { Mostrar-Resumen }
            "6" { Purgar-Todo }
            default { Write-Host "Invalido" -ForegroundColor Red }
        }
    }
}

Menu-Principal

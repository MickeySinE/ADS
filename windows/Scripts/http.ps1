# ============================================================
#   SISTEMA DE APROVISIONAMIENTO WEB - WINDOWS SERVER
#   Practica 6 | PowerShell Automatizado
#   Servidores: IIS, Apache (httpd), Nginx, Tomcat
# ============================================================

# --- Verificar permisos de Administrador ---
function Test-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host ""
    Write-Host "  ERROR: Ejecuta este script como Administrador." -ForegroundColor Red
    Write-Host "  Clic derecho -> Ejecutar con PowerShell como Administrador" -ForegroundColor Yellow
    Write-Host ""
    pause
    exit 1
}

# --- Puertos reservados ---
$puertosReservados = @(1,7,9,11,13,15,17,19,20,21,22,23,25,37,42,43,53,69,
    77,79,110,111,113,115,117,118,119,123,135,137,139,143,161,177,179,
    389,427,445,465,512,513,514,515,526,530,531,532,540,548,554,556,
    563,587,601,636,989,990,993,995,1723,2049,2222,3306,3389,5432)

$serviciosPuertos = @{
    20="FTP"; 21="FTP"; 22="SSH"; 25="SMTP"; 53="DNS";
    110="POP3"; 143="IMAP"; 445="SMB/Samba"; 2222="SSH alternativo";
    3306="MySQL/MariaDB"; 5432="PostgreSQL"; 3389="RDP"
}

# ============================================================
# FUNCIONES UTILITARIAS
# ============================================================

function Mostrar-Banner {
    Clear-Host
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Write-Host ""
    Write-Host "  ################################################################" -ForegroundColor DarkCyan
    Write-Host "  #                                                              #" -ForegroundColor DarkCyan
    Write-Host "  #       APROVISIONAMIENTO WEB  >>  WINDOWS SERVER             #" -ForegroundColor Cyan
    Write-Host "  #              Practica 6  |  PowerShell Auto                 #" -ForegroundColor Cyan
    Write-Host "  #                                                              #" -ForegroundColor DarkCyan
    Write-Host "  ################################################################" -ForegroundColor DarkCyan
    Write-Host ("  #  OS    >>  {0,-51}#" -f $os) -ForegroundColor Gray
    Write-Host ("  #  IP    >>  {0,-51}#" -f $ip) -ForegroundColor Gray
    Write-Host ("  #  Hora  >>  {0,-51}#" -f $fecha) -ForegroundColor Gray
    Write-Host "  ################################################################" -ForegroundColor DarkCyan
    Write-Host ""
}

function Mostrar-Menu {
    Write-Host "  +--------------------------------------------+" -ForegroundColor DarkYellow
    Write-Host "  |                                            |" -ForegroundColor DarkYellow
    Write-Host "  |   [INSTALACION]                            |" -ForegroundColor Yellow
    Write-Host "  |     1  >>  Instalar IIS                    |" -ForegroundColor White
    Write-Host "  |     2  >>  Instalar Apache (httpd)         |" -ForegroundColor White
    Write-Host "  |     3  >>  Instalar Nginx                  |" -ForegroundColor White
    Write-Host "  |     4  >>  Instalar Tomcat                 |" -ForegroundColor White
    Write-Host "  |                                            |" -ForegroundColor DarkYellow
    Write-Host "  |   [GESTION]                                |" -ForegroundColor Yellow
    Write-Host "  |     5  >>  Verificar servicio              |" -ForegroundColor White
    Write-Host "  |     6  >>  Desinstalar servidor            |" -ForegroundColor White
    Write-Host "  |     7  >>  Levantar / Reiniciar            |" -ForegroundColor White
    Write-Host "  |                                            |" -ForegroundColor DarkYellow
    Write-Host "  |   [SISTEMA]                                |" -ForegroundColor Yellow
    Write-Host "  |     8  >>  Purgar entorno completo         |" -ForegroundColor White
    Write-Host "  |     0  >>  Salir                           |" -ForegroundColor White
    Write-Host "  |                                            |" -ForegroundColor DarkYellow
    Write-Host "  +--------------------------------------------+" -ForegroundColor DarkYellow
    Write-Host ""
}

function Solicitar-Puerto {
    while ($true) {
        $puerto = Read-Host "  Ingrese el puerto (ej. 80, 8080, 8888)"
        if ($puerto -notmatch '^\d+$' -or [int]$puerto -le 0 -or [int]$puerto -gt 65535) {
            Write-Host "  Error: Ingresa un numero de puerto valido (1-65535)." -ForegroundColor Red
            continue
        }
        $p = [int]$puerto
        if ($puertosReservados -contains $p) {
            $desc = if ($serviciosPuertos.ContainsKey($p)) { $serviciosPuertos[$p] } else { "Sistema Critico" }
            Write-Host "  Error: Puerto $p reservado para $desc. Elige otro." -ForegroundColor Red
            continue
        }
        $ocupado = netstat -ano | Select-String ":$p "
        if ($ocupado) {
            Write-Host "  Error: El puerto $p ya esta ocupado por otro servicio." -ForegroundColor Red
            continue
        }
        return $p
    }
}

function Crear-Index {
    param($ruta, $servicio, $version, $puerto)
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>$servicio</title></head>
<body>
  <h2>$servicio</h2>
  <p>Version: $version</p>
  <p>IP: $ip</p>
  <p>Puerto: $puerto</p>
</body>
</html>
"@
    Set-Content -Path "$ruta\index.html" -Value $html -Encoding UTF8
}

function Configurar-Firewall {
    param($puerto, $nombre)
    Write-Host "  Configurando firewall: abriendo puerto $puerto..." -ForegroundColor Gray
    $ruleName = "WebServer_${nombre}_${puerto}"
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $ruleName `
        -Direction Inbound -Protocol TCP -LocalPort $puerto `
        -Action Allow -Profile Any | Out-Null
    Write-Host "  Firewall configurado. Puerto $puerto habilitado." -ForegroundColor Green
}

function Verificar-Servicio {
    param($servicio, $puerto)
    Write-Host ""
    Write-Host "  +------ Verificacion: $servicio en puerto $puerto ------+" -ForegroundColor Cyan

    $svc = Get-Service -Name $servicio -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "  [OK] Servicio $servicio : ACTIVO" -ForegroundColor Green
    } else {
        Write-Host "  [!!] Servicio $servicio : INACTIVO" -ForegroundColor Red
    }

    $escuchando = netstat -ano | Select-String ":$puerto "
    if ($escuchando) {
        Write-Host "  [OK] Puerto $puerto     : ESCUCHANDO" -ForegroundColor Green
    } else {
        Write-Host "  [??] Puerto $puerto     : No detectado aun" -ForegroundColor Yellow
    }

    Write-Host "  [>>] Encabezados HTTP:" -ForegroundColor Cyan
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:$puerto" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        Write-Host "       HTTP $($resp.StatusCode) $($resp.StatusDescription)" -ForegroundColor Green
        $resp.Headers.GetEnumerator() | Where-Object { $_.Key -match "Server|X-Frame|X-Content|X-XSS" } | ForEach-Object {
            Write-Host "       $($_.Key): $($_.Value)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "       (Servicio aun iniciando o no responde)" -ForegroundColor Yellow
    }
    Write-Host "  +---------------------------------------------------+" -ForegroundColor Cyan
}

# ============================================================
# INSTALAR IIS
# ============================================================

function Instalar-IIS {
    param($puerto)
    Write-Host ""
    Write-Host "  >> Instalando IIS en puerto $puerto..." -ForegroundColor Cyan

    $feature = Get-WindowsFeature -Name Web-Server
    if (-not $feature.Installed) {
        Write-Host "  Instalando rol Web-Server (IIS)..." -ForegroundColor Gray
        Install-WindowsFeature -Name Web-Server, Web-Common-Http, Web-Http-Errors, `
            Web-Static-Content, Web-Http-Logging, Web-Security -IncludeManagementTools | Out-Null
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $siteName = "IIS_$puerto"
    $webRoot = "C:\inetpub\wwwroot_$puerto"
    New-Item -ItemType Directory -Path $webRoot -Force | Out-Null

    Remove-WebSite -Name $siteName -ErrorAction SilentlyContinue
    New-WebSite -Name $siteName -Port $puerto -PhysicalPath $webRoot -Force | Out-Null

    $version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if (-not $version) { $version = "IIS (Windows Server)" }

    Crear-Index -ruta $webRoot -servicio "IIS" -version $version -puerto $puerto

    $webconfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <httpProtocol>
      <customHeaders>
        <add name="X-Frame-Options" value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff" />
        <add name="X-XSS-Protection" value="1; mode=block" />
        <add name="Referrer-Policy" value="no-referrer-when-downgrade" />
        <remove name="X-Powered-By" />
      </customHeaders>
    </httpProtocol>
    <security>
      <requestFiltering>
        <verbs allowUnlisted="false">
          <add verb="GET" allowed="true" />
          <add verb="POST" allowed="true" />
          <add verb="HEAD" allowed="true" />
        </verbs>
      </requestFiltering>
    </security>
  </system.webServer>
</configuration>
"@
    Set-Content -Path "$webRoot\web.config" -Value $webconfig -Encoding UTF8

    Configurar-Firewall -puerto $puerto -nombre "IIS"
    Start-WebSite -Name $siteName -ErrorAction SilentlyContinue
    Start-Service -Name W3SVC -ErrorAction SilentlyContinue

    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress
    Write-Host ""
    Write-Host "  [OK] IIS instalado y asegurado." -ForegroundColor Green
    Write-Host "       Ruta web : $webRoot" -ForegroundColor Gray
    Write-Host "       Accede en: http://$ip`:$puerto" -ForegroundColor Green

    Verificar-Servicio -servicio "W3SVC" -puerto $puerto
}

# ============================================================
# INSTALAR APACHE (descarga directa ZIP)
# ============================================================

function Instalar-Apache {
    param($puerto)
    Write-Host ""
    Write-Host "  >> Instalando Apache (httpd) en puerto $puerto..." -ForegroundColor Cyan

    $apacheDir = "C:\Apache24"
    $apacheExe = "$apacheDir\bin\httpd.exe"

    if (-not (Test-Path $apacheExe)) {
        Write-Host "  Descargando Apache desde Apache Lounge..." -ForegroundColor Gray
        $url = "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.63-240606-win64-VS17.zip"
        $zipPath = "$env:TEMP\apache.zip"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
            Write-Host "  Extrayendo Apache..." -ForegroundColor Gray
            Expand-Archive -Path $zipPath -DestinationPath "C:\" -Force
            Remove-Item $zipPath -Force
        } catch {
            Write-Host "  Error descargando Apache: $_" -ForegroundColor Red
            Write-Host "  Descarga manual: https://www.apachelounge.com/download/" -ForegroundColor Yellow
            return
        }
    }

    if (-not (Test-Path $apacheExe)) {
        Write-Host "  Error: Apache no se instalo correctamente en $apacheDir" -ForegroundColor Red
        return
    }

    $confFile = "$apacheDir\conf\httpd.conf"
    (Get-Content $confFile) -replace "^Listen \d+", "Listen $puerto" | Set-Content $confFile
    (Get-Content $confFile) -replace "^#?ServerName .*", "ServerName localhost:$puerto" | Set-Content $confFile

    $webRoot = "$apacheDir\htdocs_$puerto"
    New-Item -ItemType Directory -Path $webRoot -Force | Out-Null
    $webRootFwd = $webRoot -replace '\\', '/'
    (Get-Content $confFile) -replace 'DocumentRoot ".*"', "DocumentRoot `"$webRootFwd`"" | Set-Content $confFile
    (Get-Content $confFile) -replace '<Directory ".*htdocs.*">', "<Directory `"$webRootFwd`">" | Set-Content $confFile

    New-Item -ItemType Directory -Path "$apacheDir\conf\extra" -Force | Out-Null
    $secConf = "$apacheDir\conf\extra\security.conf"
    $secContent = @"
ServerTokens Prod
ServerSignature Off

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "no-referrer-when-downgrade"
    Header always unset X-Powered-By
</IfModule>

<Directory "/">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>
"@
    Set-Content -Path $secConf -Value $secContent -Encoding UTF8

    if (-not (Select-String -Path $confFile -Pattern "security.conf" -Quiet)) {
        Add-Content -Path $confFile -Value "`nInclude conf/extra/security.conf"
    }

    $versionOutput = & "$apacheExe" -v 2>&1
    $version = ($versionOutput | Select-String "Apache/") -replace ".*Apache/(\S+).*", '$1'
    if (-not $version) { $version = "2.4.x" }

    Crear-Index -ruta $webRoot -servicio "Apache (httpd)" -version $version -puerto $puerto

    Write-Host "  Registrando Apache como servicio de Windows..." -ForegroundColor Gray
    & "$apacheExe" -k install -n "Apache$puerto" 2>&1 | Out-Null
    Start-Service -Name "Apache$puerto" -ErrorAction SilentlyContinue

    Configurar-Firewall -puerto $puerto -nombre "Apache"

    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress
    Write-Host ""
    Write-Host "  [OK] Apache instalado y asegurado." -ForegroundColor Green
    Write-Host "       Ruta web : $webRoot" -ForegroundColor Gray
    Write-Host "       Accede en: http://$ip`:$puerto" -ForegroundColor Green

    Verificar-Servicio -servicio "Apache$puerto" -puerto $puerto
}

# ============================================================
# INSTALAR NGINX (descarga directa ZIP)
# ============================================================

function Instalar-Nginx {
    param($puerto)
    Write-Host ""
    Write-Host "  >> Instalando Nginx en puerto $puerto..." -ForegroundColor Cyan

    $nginxDir = "C:\nginx"

    if (-not (Test-Path "$nginxDir\nginx.exe")) {
        Write-Host "  Descargando Nginx para Windows..." -ForegroundColor Gray
        $url = "https://nginx.org/download/nginx-1.26.2.zip"
        $zipPath = "$env:TEMP\nginx.zip"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
            Write-Host "  Extrayendo Nginx..." -ForegroundColor Gray
            Expand-Archive -Path $zipPath -DestinationPath "$env:TEMP\nginx_extract" -Force
            $extracted = Get-ChildItem "$env:TEMP\nginx_extract" -Directory | Select-Object -First 1
            if ($extracted) {
                if (Test-Path $nginxDir) { Remove-Item $nginxDir -Recurse -Force }
                Move-Item $extracted.FullName $nginxDir -Force
            }
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\nginx_extract" -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "  Error descargando Nginx: $_" -ForegroundColor Red
            Write-Host "  Descarga manual: https://nginx.org/en/download.html" -ForegroundColor Yellow
            return
        }
    }

    if (-not (Test-Path "$nginxDir\nginx.exe")) {
        Write-Host "  Error: Nginx no se instalo correctamente en $nginxDir" -ForegroundColor Red
        return
    }

    $webRoot = "$nginxDir\html_$puerto"
    New-Item -ItemType Directory -Path $webRoot -Force | Out-Null
    $webRootFwd = $webRoot -replace '\\', '/'

    $confContent = @"
worker_processes  1;
events { worker_connections  1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;
    sendfile        on;
    keepalive_timeout  65;
    server {
        listen       $puerto;
        server_name  localhost;
        root         $webRootFwd;
        index        index.html;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        if (`$request_method !~ ^(GET|POST|HEAD)`$) {
            return 405;
        }
        location / {
            try_files `$uri `$uri/ =404;
        }
    }
}
"@
    Set-Content -Path "$nginxDir\conf\nginx.conf" -Value $confContent -Encoding UTF8

    Crear-Index -ruta $webRoot -servicio "Nginx" -version "1.26.2" -puerto $puerto

    Configurar-Firewall -puerto $puerto -nombre "Nginx"

    # Detener instancia previa si corre
    Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # Instalar como servicio con NSSM si esta disponible, sino como proceso
    $nssm = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssm) {
        & nssm install "Nginx_$puerto" "$nginxDir\nginx.exe" 2>&1 | Out-Null
        Start-Service "Nginx_$puerto" -ErrorAction SilentlyContinue
    } else {
        Start-Process -FilePath "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -WindowStyle Hidden
    }

    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress
    Write-Host ""
    Write-Host "  [OK] Nginx instalado y corriendo." -ForegroundColor Green
    Write-Host "       Ruta web : $webRoot" -ForegroundColor Gray
    Write-Host "       Accede en: http://$ip`:$puerto" -ForegroundColor Green

    Start-Sleep -Seconds 3
    # Nginx no corre como servicio nombrado sin NSSM, verificar por puerto
    $escuchando = netstat -ano | Select-String ":$puerto "
    if ($escuchando) {
        Write-Host "  [OK] Puerto $puerto : ESCUCHANDO" -ForegroundColor Green
    } else {
        Write-Host "  [??] Puerto $puerto : No detectado aun, revisa manualmente" -ForegroundColor Yellow
    }
}

# ============================================================
# INSTALAR TOMCAT (descarga directa ZIP)
# ============================================================

function Instalar-Tomcat {
    param($puerto)
    Write-Host ""
    Write-Host "  >> Instalando Tomcat en puerto $puerto..." -ForegroundColor Cyan

    # Verificar Java
    $java = Get-Command java -ErrorAction SilentlyContinue
    if (-not $java) {
        Write-Host "  Java no encontrado. Descargando OpenJDK 17..." -ForegroundColor Yellow
        $jdkUrl = "https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.msi"
        $jdkMsi = "$env:TEMP\jdk17.msi"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $jdkUrl -OutFile $jdkMsi -UseBasicParsing
            Start-Process msiexec.exe -Wait -ArgumentList "/i `"$jdkMsi`" /quiet"
            Remove-Item $jdkMsi -Force
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine")
            Write-Host "  Java instalado correctamente." -ForegroundColor Green
        } catch {
            Write-Host "  Error instalando Java: $_" -ForegroundColor Red
            Write-Host "  Instala manualmente desde https://adoptium.net/" -ForegroundColor Yellow
            return
        }
    }

    $tomcatDir = "C:\Tomcat10"

    if (-not (Test-Path "$tomcatDir\bin\catalina.bat")) {
        Write-Host "  Descargando Tomcat 10..." -ForegroundColor Gray
        $url = "https://downloads.apache.org/tomcat/tomcat-10/v10.1.26/bin/apache-tomcat-10.1.26-windows-x64.zip"
        $zipPath = "$env:TEMP\tomcat.zip"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
            Write-Host "  Extrayendo Tomcat..." -ForegroundColor Gray
            Expand-Archive -Path $zipPath -DestinationPath "$env:TEMP\tomcat_extract" -Force
            $extracted = Get-ChildItem "$env:TEMP\tomcat_extract" | Select-Object -First 1
            if (Test-Path $tomcatDir) { Remove-Item $tomcatDir -Recurse -Force }
            Move-Item $extracted.FullName $tomcatDir -Force
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\tomcat_extract" -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "  Error descargando Tomcat: $_" -ForegroundColor Red
            Write-Host "  Descarga manual: https://tomcat.apache.org/download-10.cgi" -ForegroundColor Yellow
            return
        }
    }

    if (-not (Test-Path "$tomcatDir\bin\catalina.bat")) {
        Write-Host "  Error: Tomcat no se instalo correctamente en $tomcatDir" -ForegroundColor Red
        return
    }

    # Configurar puerto en server.xml
    $serverXml = "$tomcatDir\conf\server.xml"
    (Get-Content $serverXml) -replace 'port="8080"', "port=`"$puerto`"" | Set-Content $serverXml

    # Crear index
    $webRoot = "$tomcatDir\webapps\ROOT"
    New-Item -ItemType Directory -Path $webRoot -Force | Out-Null
    # Eliminar index.jsp para que sirva el index.html
    Remove-Item "$webRoot\index.jsp" -Force -ErrorAction SilentlyContinue
    Crear-Index -ruta $webRoot -servicio "Tomcat" -version "10.1.26" -puerto $puerto

    # Instalar como servicio Windows
    $serviceScript = "$tomcatDir\bin\service.bat"
    if (Test-Path $serviceScript) {
        $env:CATALINA_HOME = $tomcatDir
        $env:JRE_HOME = (Get-Command java -ErrorAction SilentlyContinue | Split-Path | Split-Path)
        Write-Host "  Registrando Tomcat como servicio..." -ForegroundColor Gray
        & cmd /c "`"$serviceScript`" install Tomcat$puerto" 2>&1 | Out-Null
        Start-Service -Name "Tomcat$puerto" -ErrorAction SilentlyContinue
    } else {
        Write-Host "  Iniciando Tomcat directamente..." -ForegroundColor Yellow
        $env:CATALINA_HOME = $tomcatDir
        Start-Process -FilePath "$tomcatDir\bin\startup.bat" -WorkingDirectory "$tomcatDir\bin" -WindowStyle Hidden
    }

    Configurar-Firewall -puerto $puerto -nombre "Tomcat"

    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress
    Write-Host ""
    Write-Host "  [OK] Tomcat instalado." -ForegroundColor Green
    Write-Host "       Ruta web : $webRoot" -ForegroundColor Gray
    Write-Host "       Accede en: http://$ip`:$puerto" -ForegroundColor Green

    Start-Sleep -Seconds 5
    $svcName = (Get-Service | Where-Object { $_.Name -like "Tomcat*" } | Select-Object -First 1).Name
    if ($svcName) {
        Verificar-Servicio -servicio $svcName -puerto $puerto
    } else {
        $escuchando = netstat -ano | Select-String ":$puerto "
        if ($escuchando) {
            Write-Host "  [OK] Puerto $puerto : ESCUCHANDO" -ForegroundColor Green
        } else {
            Write-Host "  [??] Puerto $puerto : Tomcat puede tardar unos segundos en iniciar" -ForegroundColor Yellow
        }
    }
}

# ============================================================
# DESINSTALAR SERVIDOR
# ============================================================

function Desinstalar-Servidor {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "    Desinstalar servidor especifico" -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "  1) IIS   2) Apache   3) Nginx   4) Tomcat"
    Write-Host ""
    $op = Read-Host "  Selecciona el servidor (1-4)"

    switch ($op) {
        "1" {
            Write-Host "  Desinstalando IIS..." -ForegroundColor Yellow
            Stop-Service W3SVC -ErrorAction SilentlyContinue
            Uninstall-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
            Remove-Item "C:\inetpub\wwwroot_*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] IIS desinstalado." -ForegroundColor Green
        }
        "2" {
            Write-Host "  Desinstalando Apache..." -ForegroundColor Yellow
            Get-Service | Where-Object { $_.Name -like "Apache*" } | ForEach-Object {
                Stop-Service $_.Name -ErrorAction SilentlyContinue
                & "C:\Apache24\bin\httpd.exe" -k uninstall -n $_.Name 2>&1 | Out-Null
            }
            Remove-Item "C:\Apache24" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Apache desinstalado." -ForegroundColor Green
        }
        "3" {
            Write-Host "  Desinstalando Nginx..." -ForegroundColor Yellow
            Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force
            Get-Service | Where-Object { $_.Name -like "Nginx*" } | ForEach-Object {
                Stop-Service $_.Name -ErrorAction SilentlyContinue
            }
            Remove-Item "C:\nginx" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Nginx desinstalado." -ForegroundColor Green
        }
        "4" {
            Write-Host "  Desinstalando Tomcat..." -ForegroundColor Yellow
            Get-Service | Where-Object { $_.Name -like "Tomcat*" } | ForEach-Object {
                Stop-Service $_.Name -ErrorAction SilentlyContinue
                $env:CATALINA_HOME = "C:\Tomcat10"
                & cmd /c "`"C:\Tomcat10\bin\service.bat`" remove $($_.Name)" 2>&1 | Out-Null
            }
            Remove-Item "C:\Tomcat10" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Tomcat desinstalado." -ForegroundColor Green
        }
        default { Write-Host "  Opcion invalida." -ForegroundColor Red }
    }
}

# ============================================================
# LEVANTAR / REINICIAR SERVICIO
# ============================================================

function Levantar-Servicio {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "    Levantar / Reiniciar servicio" -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan

    $instalados = @()
    if (Get-Service W3SVC -ErrorAction SilentlyContinue)          { $instalados += "1) IIS (W3SVC)" }
    if (Test-Path "C:\Apache24\bin\httpd.exe")                     { $instalados += "2) Apache (httpd)" }
    if (Test-Path "C:\nginx\nginx.exe")                            { $instalados += "3) Nginx" }
    if (Test-Path "C:\Tomcat10\bin\catalina.bat")                  { $instalados += "4) Tomcat" }

    if ($instalados.Count -eq 0) {
        Write-Host "  No hay ningun servidor instalado." -ForegroundColor Yellow
        return
    }

    Write-Host "  Servicios instalados:"; Write-Host ""
    $instalados | ForEach-Object { Write-Host "    $_" }
    Write-Host ""

    $op = Read-Host "  Selecciona el servicio (1-4)"
    $puerto = Read-Host "  Ingresa el puerto en el que debe correr"
    if ($puerto -notmatch '^\d+$') { Write-Host "  Puerto invalido." -ForegroundColor Red; return }
    $p = [int]$puerto

    switch ($op) {
        "1" {
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            Configurar-Firewall -puerto $p -nombre "IIS"
            Restart-Service W3SVC
            Write-Host "  [OK] IIS reiniciado en puerto $p." -ForegroundColor Green
            Verificar-Servicio -servicio "W3SVC" -puerto $p
        }
        "2" {
            $confFile = "C:\Apache24\conf\httpd.conf"
            (Get-Content $confFile) -replace "^Listen \d+", "Listen $p" | Set-Content $confFile
            Configurar-Firewall -puerto $p -nombre "Apache"
            Get-Service | Where-Object { $_.Name -like "Apache*" } | Restart-Service -ErrorAction SilentlyContinue
            Write-Host "  [OK] Apache reiniciado en puerto $p." -ForegroundColor Green
            $svcName = (Get-Service | Where-Object { $_.Name -like "Apache*" } | Select-Object -First 1).Name
            Verificar-Servicio -servicio $svcName -puerto $p
        }
        "3" {
            $webRootFwd = "C:/nginx/html_$p"
            $confContent = @"
worker_processes  1;
events { worker_connections  1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;
    sendfile        on;
    keepalive_timeout  65;
    server {
        listen       $p;
        server_name  localhost;
        root         $webRootFwd;
        index        index.html;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        location / { try_files `$uri `$uri/ =404; }
    }
}
"@
            Set-Content -Path "C:\nginx\conf\nginx.conf" -Value $confContent -Encoding UTF8
            Configurar-Firewall -puerto $p -nombre "Nginx"
            Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Seconds 1
            Start-Process -FilePath "C:\nginx\nginx.exe" -WorkingDirectory "C:\nginx" -WindowStyle Hidden
            Write-Host "  [OK] Nginx reiniciado en puerto $p." -ForegroundColor Green
        }
        "4" {
            $serverXml = "C:\Tomcat10\conf\server.xml"
            (Get-Content $serverXml) -replace 'port="\d+"', "port=`"$p`"" | Set-Content $serverXml
            Configurar-Firewall -puerto $p -nombre "Tomcat"
            Get-Service | Where-Object { $_.Name -like "Tomcat*" } | Restart-Service -ErrorAction SilentlyContinue
            Write-Host "  [OK] Tomcat reiniciado en puerto $p." -ForegroundColor Green
            $svcName = (Get-Service | Where-Object { $_.Name -like "Tomcat*" } | Select-Object -First 1).Name
            if ($svcName) { Verificar-Servicio -servicio $svcName -puerto $p }
        }
        default { Write-Host "  Opcion invalida." -ForegroundColor Red }
    }
}

# ============================================================
# FLUJO VERIFICACION
# ============================================================

function Flujo-Verificacion {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "    Verificacion de servicio" -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "  1) IIS (W3SVC)   2) Apache   3) Nginx   4) Tomcat"
    Write-Host ""
    $op = Read-Host "  Selecciona el servicio (1-4)"
    $puerto = Read-Host "  Ingresa el puerto del servicio"
    if ($puerto -notmatch '^\d+$') { Write-Host "  Puerto invalido." -ForegroundColor Red; return }

    switch ($op) {
        "1" { Verificar-Servicio -servicio "W3SVC" -puerto ([int]$puerto) }
        "2" {
            $svcName = (Get-Service | Where-Object { $_.Name -like "Apache*" } | Select-Object -First 1).Name
            if ($svcName) { Verificar-Servicio -servicio $svcName -puerto ([int]$puerto) }
            else { Write-Host "  Apache no esta instalado." -ForegroundColor Yellow }
        }
        "3" {
            $escuchando = netstat -ano | Select-String ":$puerto "
            if ($escuchando) { Write-Host "  [OK] Nginx escuchando en puerto $puerto" -ForegroundColor Green }
            else { Write-Host "  [??] Nginx no detectado en puerto $puerto" -ForegroundColor Yellow }
        }
        "4" {
            $svcName = (Get-Service | Where-Object { $_.Name -like "Tomcat*" } | Select-Object -First 1).Name
            if ($svcName) { Verificar-Servicio -servicio $svcName -puerto ([int]$puerto) }
            else { Write-Host "  Tomcat no esta instalado." -ForegroundColor Yellow }
        }
        default { Write-Host "  Opcion invalida." -ForegroundColor Red }
    }
}

# ============================================================
# LIMPIAR ENTORNO
# ============================================================

function Limpiar-Entorno {
    Write-Host ""
    Write-Host "  Limpiando entorno completo..." -ForegroundColor Yellow

    Stop-Service W3SVC -ErrorAction SilentlyContinue
    Uninstall-WindowsFeature -Name Web-Server -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    Remove-Item "C:\inetpub\wwwroot_*" -Recurse -Force -ErrorAction SilentlyContinue

    Get-Service | Where-Object { $_.Name -like "Apache*" } | ForEach-Object {
        Stop-Service $_.Name -ErrorAction SilentlyContinue
        & "C:\Apache24\bin\httpd.exe" -k uninstall -n $_.Name 2>&1 | Out-Null
    }
    Remove-Item "C:\Apache24" -Recurse -Force -ErrorAction SilentlyContinue

    Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force
    Remove-Item "C:\nginx" -Recurse -Force -ErrorAction SilentlyContinue

    Get-Service | Where-Object { $_.Name -like "Tomcat*" } | ForEach-Object {
        Stop-Service $_.Name -ErrorAction SilentlyContinue
        & cmd /c "`"C:\Tomcat10\bin\service.bat`" remove $($_.Name)" 2>&1 | Out-Null
    }
    Remove-Item "C:\Tomcat10" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "  [OK] Entorno limpiado completamente." -ForegroundColor Green
}

# ============================================================
# FLUJO INSTALACION
# ============================================================

function Flujo-Instalacion {
    param($tipo, $nombre)
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "    Instalacion de $nombre" -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan

    $puerto = Solicitar-Puerto
    Write-Host "  Puerto seleccionado: $puerto"; Write-Host ""

    $conf = Read-Host "  Confirmar instalacion de $nombre en puerto $puerto? [s/N]"
    if ($conf -notmatch '^[sS]$') { Write-Host "  Instalacion cancelada."; return }

    switch ($tipo) {
        "iis"    { Instalar-IIS    -puerto $puerto }
        "apache" { Instalar-Apache -puerto $puerto }
        "nginx"  { Instalar-Nginx  -puerto $puerto }
        "tomcat" { Instalar-Tomcat -puerto $puerto }
    }
}

# ============================================================
# MAIN - LOOP PRINCIPAL
# ============================================================

while ($true) {
    Mostrar-Banner
    Mostrar-Menu

    $opcion = Read-Host "  Opcion"

    switch ($opcion) {
        "1" { Flujo-Instalacion -tipo "iis"    -nombre "IIS" }
        "2" { Flujo-Instalacion -tipo "apache" -nombre "Apache (httpd)" }
        "3" { Flujo-Instalacion -tipo "nginx"  -nombre "Nginx" }
        "4" { Flujo-Instalacion -tipo "tomcat" -nombre "Tomcat" }
        "5" { Flujo-Verificacion }
        "6" { Desinstalar-Servidor }
        "7" { Levantar-Servicio }
        "8" {
            $conf = Read-Host "  Seguro que deseas purgar todos los servidores? [s/N]"
            if ($conf -match '^[sS]$') { Limpiar-Entorno }
        }
        "0" {
            Write-Host ""
            Write-Host "  Saliendo. Hasta luego!" -ForegroundColor Cyan
            Write-Host ""
            exit 0
        }
        default { Write-Host "  Opcion invalida. Ingresa un numero del 0 al 8." -ForegroundColor Red }
    }

    Write-Host ""
    Read-Host "  Presiona ENTER para volver al menu"
}

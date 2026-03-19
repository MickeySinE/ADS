# http_funciones.ps1

$APACHE_WEBROOT = "C:\Apache24\htdocs"
$APACHE_CONF    = "C:\Apache24\conf\httpd.conf"
$NGINX_WEBROOT  = "C:\nginx\html"
$NGINX_CONF     = "C:\nginx\conf\nginx.conf"
$TOMCAT_HOME    = "C:\tomcat"
$IIS_WEBROOT    = "C:\inetpub\wwwroot"
$PUERTOS_RESERVADOS = @(21,22,23,25,53,67,68,110,143,161,443,445,3306,5432,8443)

function Verificar-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[ERROR] Se requieren privilegios de administrador."
        return $false
    }
    return $true
}

function Validar-Puerto($puerto) {
    if ($puerto -notmatch '^\d+$') { Write-Host "[ERROR] Solo numeros." ; return $false }
    $p = [int]$puerto
    if ($p -lt 1 -or $p -gt 65535) { Write-Host "[ERROR] Rango 1-65535." ; return $false }
    if ($PUERTOS_RESERVADOS -contains $p) { Write-Host "[ERROR] Puerto $p reservado." ; return $false }
    $enUso = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $p }
    if ($enUso) { Write-Host "[ERROR] Puerto $p ya en uso." ; return $false }
    return $true
}

function Leer-Puerto {
    while ($true) {
        $input = (Read-Host "  Puerto de escucha").Trim()
        if (Validar-Puerto $input) { return [int]$input }
    }
}

function Configurar-Firewall($puerto, $nombreRegla) {
    $existente = Get-NetFirewallRule -DisplayName $nombreRegla -ErrorAction SilentlyContinue
    if ($existente) { Remove-NetFirewallRule -DisplayName $nombreRegla -ErrorAction SilentlyContinue }
    New-NetFirewallRule -DisplayName $nombreRegla -Direction Inbound -Protocol TCP -LocalPort $puerto -Action Allow -ErrorAction SilentlyContinue | Out-Null
}

function Crear-IndexHtml($servicio, $version, $puerto, $ruta) {
    if (-not (Test-Path $ruta)) { New-Item -ItemType Directory -Path $ruta -Force | Out-Null }
    $contenido = @"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$servicio - Practica 6</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&family=Syne:wght@700;800&display=swap');
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --bg:      #1e1e2e;
      --surface: #313244;
      --border:  #45475a;
      --text:    #cdd6f4;
      --muted:   #6c7086;
      --blue:    #89b4fa;
      --green:   #a6e3a1;
      --red:     #f38ba8;
      --yellow:  #f9e2af;
    }
    body {
      background: var(--bg);
      color: var(--text);
      font-family: 'JetBrains Mono', monospace;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 2rem;
    }
    body::before {
      content: '';
      position: fixed;
      inset: 0;
      background:
        radial-gradient(ellipse 60% 40% at 20% 30%, rgba(137,180,250,0.07) 0%, transparent 60%),
        radial-gradient(ellipse 50% 35% at 80% 70%, rgba(166,227,161,0.05) 0%, transparent 55%);
      pointer-events: none;
    }
    .card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-left: 4px solid var(--blue);
      border-radius: 12px;
      padding: 2.5rem 3rem;
      max-width: 480px;
      width: 100%;
      box-shadow: 0 24px 60px rgba(0,0,0,0.4);
      animation: fadeUp .5s ease both;
    }
    @keyframes fadeUp {
      from { opacity:0; transform: translateY(20px); }
      to   { opacity:1; transform: translateY(0); }
    }
    .title {
      font-family: 'Syne', sans-serif;
      font-size: 1.4rem;
      font-weight: 800;
      color: var(--blue);
      letter-spacing: .02em;
      margin-bottom: 1.8rem;
      text-align: center;
    }
    .row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: .55rem 0;
      border-bottom: 1px solid rgba(69,71,90,0.5);
      font-size: .9rem;
    }
    .row:last-child { border-bottom: none; }
    .label { color: var(--muted); }
    .val-server  { color: var(--green);  font-weight: 700; }
    .val-version { color: var(--yellow); font-weight: 700; }
    .val-port    { color: var(--red);    font-weight: 700; }
    .footer {
      margin-top: 1.8rem;
      text-align: center;
      font-size: .75rem;
      color: var(--muted);
      letter-spacing: .04em;
    }
    .dot {
      display: inline-block;
      width: 7px; height: 7px;
      border-radius: 50%;
      background: var(--green);
      margin-right: .4rem;
      box-shadow: 0 0 6px var(--green);
      animation: pulse 2s ease-in-out infinite;
    }
    @keyframes pulse {
      0%,100% { opacity:1; } 50% { opacity:.3; }
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="title">Servidor HTTP &mdash; Practica 6</div>
    <div class="row">
      <span class="label">Servidor</span>
      <span class="val-server">$servicio</span>
    </div>
    <div class="row">
      <span class="label">Version</span>
      <span class="val-version">$version</span>
    </div>
    <div class="row">
      <span class="label">Puerto</span>
      <span class="val-port">$puerto</span>
    </div>
    <div class="footer">
      <span class="dot"></span>Desplegado via SSH &mdash; Script automatizado
    </div>
  </div>
</body>
</html>
"@
    [System.IO.File]::WriteAllText("$ruta\index.html", $contenido, [System.Text.UTF8Encoding]::new($false))
}

function Configurar-UsuarioDedicado($usuario, $webroot) {
    $existe = Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue
    if (-not $existe) {
        $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%'
        $pwd = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
        $secPwd = ConvertTo-SecureString $pwd -AsPlainText -Force
        New-LocalUser -Name $usuario -Password $secPwd -PasswordNeverExpires -UserMayNotChangePassword `
            -Description "Usuario dedicado servicio web" -ErrorAction SilentlyContinue | Out-Null
    }
    if (-not (Test-Path $webroot)) { New-Item -ItemType Directory -Path $webroot -Force | Out-Null }
    $acl = Get-Acl $webroot
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
    $reglas = @(
        [System.Security.AccessControl.FileSystemAccessRule]::new("SYSTEM",       "FullControl",    "ContainerInherit,ObjectInherit", "None", "Allow"),
        [System.Security.AccessControl.FileSystemAccessRule]::new("Administrators","FullControl",    "ContainerInherit,ObjectInherit", "None", "Allow"),
        [System.Security.AccessControl.FileSystemAccessRule]::new($usuario,        "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    )
    foreach ($r in $reglas) { $acl.AddAccessRule($r) }
    Set-Acl -Path $webroot -AclObject $acl -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────
#  IIS
# ─────────────────────────────────────────

function Instalar-IIS {
    if (-not (Verificar-Admin)) { return }
    $puerto = Leer-Puerto

    Write-Host "  Instalando componentes IIS..."
    $yaInstalado = (Get-WindowsFeature -Name "Web-Server" -ErrorAction SilentlyContinue).Installed
    if (-not $yaInstalado) {
        $features = @(
            "Web-Server","Web-Common-Http","Web-Default-Doc","Web-Static-Content",
            "Web-Http-Errors","Web-Http-Logging","Web-Stat-Compression","Web-Filtering",
            "Web-Mgmt-Tools","Web-Mgmt-Console","Web-Scripting-Tools"
        )
        Install-WindowsFeature -Name $features -ErrorAction SilentlyContinue | Out-Null
    } else {
        Write-Host "  IIS ya instalado, configurando sitio HTTP..."
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $binding = Get-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue
    if ($binding) {
        Remove-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue
    }
    New-WebBinding -Name "Default Web Site" -Protocol http -Port $puerto -IPAddress "*" -ErrorAction SilentlyContinue | Out-Null

    $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if (-not $ver) { $ver = (Get-WindowsFeature Web-Server -ErrorAction SilentlyContinue).Description }

    Crear-IndexHtml "IIS" $ver $puerto $IIS_WEBROOT
    Configurar-UsuarioDedicado "iis_svc" $IIS_WEBROOT

    # IIS requiere IIS_IUSRS e IUSR + ApplicationPoolIdentity para que el worker process funcione
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $acl = Get-Acl $IIS_WEBROOT
    $acl.SetAccessRuleProtection($false, $true)
    foreach ($cuenta in @("IIS_IUSRS", "IUSR", "IIS AppPool\DefaultAppPool")) {
        try {
            $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                $cuenta, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.AddAccessRule($rule)
        } catch {}
    }
    Set-Acl $IIS_WEBROOT $acl

    # Seguridad via appcmd (no tocar applicationHost.config directamente)
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:httpProtocol "/-customHeaders.[name='X-Powered-By']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:httpProtocol "/+customHeaders.[name='X-Frame-Options',value='SAMEORIGIN']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:httpProtocol "/+customHeaders.[name='X-Content-Type-Options',value='nosniff']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:httpProtocol "/+customHeaders.[name='X-XSS-Protection',value='1; mode=block']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:requestFiltering "/+verbs.[verb='TRACE',allowed='false']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:requestFiltering "/+verbs.[verb='TRACK',allowed='false']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:requestFiltering "/+verbs.[verb='DELETE',allowed='false']" 2>&1 | Out-Null
    # Ocultar version del servidor en encabezado Server (IIS no permite mostrar nombre sin version)
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:system.webServer/security/requestFiltering /removeServerHeader:true 2>&1 | Out-Null

    Configurar-Firewall $puerto "IIS HTTP"

    Start-Service W3SVC -ErrorAction SilentlyContinue
    Start-Sleep 2

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $pool = Get-Item "IIS:\AppPools\DefaultAppPool" -ErrorAction SilentlyContinue
    if ($pool) {
        if ($pool.state -ne "Started") {
            Start-WebItem "IIS:\AppPools\DefaultAppPool" -ErrorAction SilentlyContinue
            Start-Sleep 2
        }
    }
    $site = Get-Item "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue
    if ($site -and $site.state -ne "Started") {
        Start-WebItem "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue
        Start-Sleep 1
    }

    $svc = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "[OK] IIS instalado y activo en el puerto $puerto."
    } else {
        Write-Host "[ERROR] IIS instalado pero no pudo iniciarse."
    }
}

function Estado-IIS {
    $svc = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    if ($svc) { Write-Host "  Servicio IIS (W3SVC) - Estado: $($svc.Status)" }
    else { Write-Host "  IIS no esta instalado." ; return }
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $binding = Get-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($binding) {
        $puerto = $binding.bindingInformation.Split(":")[1]
        Write-Host "  Puerto configurado: $puerto"
        try { $r = Invoke-WebRequest "http://localhost:$puerto" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
              Write-Host "  HTTP $($r.StatusCode) - Respondiendo correctamente." } catch {}
    }
}

function Reiniciar-IIS {
    if (-not (Verificar-Admin)) { return }
    & iisreset /restart 2>&1 | Out-Null
    Start-Sleep 3
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $pool = Get-Item "IIS:\AppPools\DefaultAppPool" -ErrorAction SilentlyContinue
    if ($pool -and $pool.state -ne "Started") { Start-WebItem "IIS:\AppPools\DefaultAppPool" -ErrorAction SilentlyContinue }
    $site = Get-Item "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue
    if ($site -and $site.state -ne "Started") { Start-WebItem "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue }
    $svc = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") { Write-Host "[OK] IIS reiniciado." }
    else { Write-Host "[ERROR] IIS no pudo reiniciarse." }
}

function Reconfigurar-IIS {
    if (-not (Verificar-Admin)) { return }
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $binding = Get-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $binding) { Write-Host "[ERROR] IIS no instalado o sin sitio configurado." ; return }
    $actual = $binding.bindingInformation.Split(":")[1]
    Write-Host "  Puerto actual: $actual"
    $nuevo = Leer-Puerto
    Remove-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue
    New-WebBinding -Name "Default Web Site" -Protocol http -Port $nuevo -IPAddress "*" | Out-Null
    $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    Crear-IndexHtml "IIS" $ver $nuevo $IIS_WEBROOT
    Configurar-Firewall $nuevo "IIS HTTP"
    & iisreset /restart 2>&1 | Out-Null
    Start-Sleep 3
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $pool = Get-Item "IIS:\AppPools\DefaultAppPool" -ErrorAction SilentlyContinue
    if ($pool -and $pool.state -ne "Started") { Start-WebItem "IIS:\AppPools\DefaultAppPool" -ErrorAction SilentlyContinue }
    $site = Get-Item "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue
    if ($site -and $site.state -ne "Started") { Start-WebItem "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue }
    $svc = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") { Write-Host "[OK] IIS reconfigurado en el puerto $nuevo." }
    else { Write-Host "[ERROR] IIS no pudo reiniciarse." }
}

# ─────────────────────────────────────────
#  TOMCAT
# ─────────────────────────────────────────

function Obtener-VersionesTomcat {
    $ramas = @(9, 10, 11)
    $etiquetas = @{9="LTS"; 10="Latest"; 11="Desarrollo"}
    $resultado = @()
    foreach ($rama in $ramas) {
        $fallback = @{9="9.0.98"; 10="10.1.34"; 11="11.0.2"}
        try {
            $html = Invoke-WebRequest -Uri "https://downloads.apache.org/tomcat/tomcat-${rama}/" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            $ultima = ($html.Links.href | Where-Object { $_ -match '^v[\d\.]+/$' } | Sort-Object | Select-Object -Last 1).TrimEnd('/').TrimStart('v')
            if (-not $ultima) { $ultima = $fallback[$rama] }
        } catch { $ultima = $fallback[$rama] }
        $resultado += [PSCustomObject]@{ Rama=$rama; Version=$ultima; Etiqueta=$etiquetas[$rama] }
    }
    return $resultado
}

function Instalar-Tomcat {
    if (-not (Verificar-Admin)) { return }

    Write-Host ""
    Write-Host "  Versiones disponibles de Tomcat:"
    $versiones = Obtener-VersionesTomcat
    for ($i = 0; $i -lt $versiones.Count; $i++) {
        Write-Host ("  {0,2}) Tomcat {1} {2} ({3})" -f ($i+1), $versiones[$i].Rama, $versiones[$i].Etiqueta, $versiones[$i].Version)
    }
    Write-Host ""
    $sel = $null
    while ($true) {
        $input = (Read-Host "  Opcion [1-3]").Trim()
        if ($input -match '^[123]$') { $sel = [int]$input - 1; break }
        Write-Host "[ERROR] Elige 1, 2 o 3."
    }
    $rama   = $versiones[$sel].Rama
    $ver    = $versiones[$sel].Version
    $puerto = Leer-Puerto

    # Buscar Java: primero en PATH, luego en C:\jdk17, luego descargar
    $javaOk = $false
    try { & java -version 2>&1 | Out-Null; $javaOk = $true } catch {}

    if (-not $javaOk) {
        # Buscar en C:\jdk17 (instalacion manual previa)
        $jdkDir = Get-ChildItem "C:\jdk17" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $jdkDir) {
            # Buscar en Program Files
            $javaExe = Get-ChildItem "C:\Program Files\" -Recurse -Filter "java.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($javaExe) { $jdkDir = [PSCustomObject]@{ FullName = $javaExe.DirectoryName -replace "\\bin$","" } }
        }
        if ($jdkDir) {
            Write-Host "  Java encontrado en: $($jdkDir.FullName)"
            $env:JAVA_HOME = $jdkDir.FullName
            $env:Path = "$($jdkDir.FullName)\bin;$env:Path"
            [Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkDir.FullName, "Machine")
            [Environment]::SetEnvironmentVariable("Path", "$($jdkDir.FullName)\bin;" + [Environment]::GetEnvironmentVariable("Path","Machine"), "Machine")
        } else {
            Write-Host "  Java no encontrado. Descargando OpenJDK 17 (Azul Zulu)..."
            $jdkZip = "C:\jdk17.zip"
            try {
                Invoke-WebRequest -Uri "https://cdn.azul.com/zulu/bin/zulu17.50.19-ca-jdk17.0.11-win_x64.zip" `
                    -OutFile $jdkZip -UseBasicParsing -ErrorAction Stop
                if (Test-Path "C:\jdk17") { Remove-Item "C:\jdk17" -Recurse -Force }
                Expand-Archive -Path $jdkZip -DestinationPath "C:\jdk17" -Force
                $jdkDir = Get-ChildItem "C:\jdk17" -Directory | Select-Object -First 1
                $env:JAVA_HOME = $jdkDir.FullName
                $env:Path = "$($jdkDir.FullName)\bin;$env:Path"
                [Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkDir.FullName, "Machine")
                [Environment]::SetEnvironmentVariable("Path", "$($jdkDir.FullName)\bin;" + [Environment]::GetEnvironmentVariable("Path","Machine"), "Machine")
                Remove-Item $jdkZip -Force -ErrorAction SilentlyContinue
                Write-Host "  Java instalado en $($jdkDir.FullName)"
            } catch { Write-Host "[ERROR] No se pudo instalar Java." ; return }
        }
    }

    $url    = "https://downloads.apache.org/tomcat/tomcat-${rama}/v${ver}/bin/apache-tomcat-${ver}.zip"
    $tmpZip = "$env:TEMP\tomcat.zip"
    Write-Host "  Descargando Tomcat $ver..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop
    } catch { Write-Host "[ERROR] Descarga fallida." ; return }

    if (Test-Path $TOMCAT_HOME) { Remove-Item $TOMCAT_HOME -Recurse -Force }
    Expand-Archive -Path $tmpZip -DestinationPath "C:\" -Force
    $extracted = Get-ChildItem "C:\" -Directory | Where-Object { $_.Name -like "apache-tomcat-*" } | Select-Object -First 1
    if ($extracted) { Rename-Item $extracted.FullName $TOMCAT_HOME }
    Remove-Item $tmpZip -Force

    if (-not (Test-Path "$TOMCAT_HOME\bin\catalina.bat")) { Write-Host "[ERROR] Instalacion de Tomcat fallida." ; return }

    $serverXml = "$TOMCAT_HOME\conf\server.xml"
    (Get-Content $serverXml) -replace 'port="8080"', "port=`"$puerto`"" |
        ForEach-Object { $_ -replace 'protocol="HTTP/1\.1"', 'protocol="HTTP/1.1" server="Tomcat" xpoweredBy="false"' } |
        Set-Content $serverXml -Encoding UTF8

    Remove-Item "$TOMCAT_HOME\webapps\ROOT\index.jsp" -Force -ErrorAction SilentlyContinue
    Crear-IndexHtml "Tomcat" $ver $puerto "$TOMCAT_HOME\webapps\ROOT"
    Configurar-UsuarioDedicado "tomcat_svc" "$TOMCAT_HOME\webapps"

    # Configurar encabezados de seguridad en web.xml
    $webXml = "$TOMCAT_HOME\conf\web.xml"
    if (Test-Path $webXml) {
        $contenido = Get-Content $webXml -Raw
        $contenido = $contenido -replace '(?s)<!--\s*\r?\n(\s*<filter>\s*\r?\n\s*<filter-name>httpHeaderSecurity</filter-name>.*?</filter>\s*\r?\n)\s*-->', '$1'
        $contenido = $contenido -replace '(?s)<!--\s*\r?\n(\s*<filter-mapping>\s*\r?\n\s*<filter-name>httpHeaderSecurity</filter-name>.*?</filter-mapping>\s*\r?\n)\s*-->', '$1'
        $contenido = $contenido -replace 'org\.apache\.catalina\.filters\.HttpHeaderSecurityFilter</filter-class>', 'org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class><init-param><param-name>antiClickJackingEnabled</param-name><param-value>true</param-value></init-param><init-param><param-name>antiClickJackingOption</param-name><param-value>SAMEORIGIN</param-value></init-param><init-param><param-name>blockContentTypeSniffingEnabled</param-name><param-value>true</param-value></init-param>'
        if ($contenido -notmatch "HttpHeaderSecurityFilter") {
            $contenido = $contenido -replace '</web-app>', '<filter><filter-name>httpHeaderSecurity</filter-name><filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class><init-param><param-name>antiClickJackingEnabled</param-name><param-value>true</param-value></init-param><init-param><param-name>antiClickJackingOption</param-name><param-value>SAMEORIGIN</param-value></init-param><init-param><param-name>blockContentTypeSniffingEnabled</param-name><param-value>true</param-value></init-param></filter><filter-mapping><filter-name>httpHeaderSecurity</filter-name><url-pattern>/*</url-pattern></filter-mapping></web-app>'
        }
        [System.IO.File]::WriteAllText($webXml, $contenido, [System.Text.UTF8Encoding]::new($false))
    }

    $javaHome = $env:JAVA_HOME
    if (-not $javaHome) { $javaHome = (Get-Command java -ErrorAction SilentlyContinue).Source -replace '\\bin\\java.exe','' }
    $env:JAVA_HOME     = $javaHome
    $env:CATALINA_HOME = $TOMCAT_HOME
    $env:CATALINA_OUT  = "$TOMCAT_HOME\logs\catalina.out"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$TOMCAT_HOME\bin\catalina.bat`" start" `
        -WorkingDirectory "$TOMCAT_HOME\bin" -WindowStyle Hidden -ErrorAction SilentlyContinue
    Start-Sleep 10
    Configurar-Firewall $puerto "Tomcat HTTP"

    try {
        Invoke-WebRequest "http://localhost:$puerto" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop | Out-Null
        Write-Host "[OK] Tomcat $ver instalado y activo en el puerto $puerto."
    } catch {
        Write-Host "[ERROR] Tomcat instalado pero no responde. Revisa: $TOMCAT_HOME\logs\catalina.out"
    }
}

function Estado-Tomcat {
    $proc = Get-Process -Name "java" -ErrorAction SilentlyContinue
    if ($proc) { Write-Host "  Tomcat corriendo como proceso Java (PID: $($proc[0].Id))." }
    else { Write-Host "  Tomcat no esta en ejecucion." }
    if (Test-Path "$TOMCAT_HOME\conf\server.xml") {
        $puerto = ([xml](Get-Content "$TOMCAT_HOME\conf\server.xml")).Server.Service.Connector |
                  Where-Object { $_.protocol -like "HTTP*" } | Select-Object -First 1 -ExpandProperty port
        if ($puerto) {
            Write-Host "  Puerto configurado: $puerto"
            try { $r = Invoke-WebRequest "http://localhost:$puerto" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
                  Write-Host "  HTTP $($r.StatusCode) - Respondiendo correctamente." } catch {}
        }
    }
}

function Reiniciar-Tomcat {
    if (-not (Verificar-Admin)) { return }
    Get-Process -Name "java" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 2
    $env:CATALINA_HOME = $TOMCAT_HOME
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$TOMCAT_HOME\bin\catalina.bat`" start" `
        -WorkingDirectory "$TOMCAT_HOME\bin" -WindowStyle Hidden -ErrorAction SilentlyContinue
    Start-Sleep 10
    $proc = Get-Process -Name "java" -ErrorAction SilentlyContinue
    if ($proc) { Write-Host "[OK] Tomcat reiniciado." }
    else { Write-Host "[ERROR] Tomcat no pudo reiniciarse." }
}

function Reconfigurar-Tomcat {
    if (-not (Verificar-Admin)) { return }
    if (-not (Test-Path "$TOMCAT_HOME\conf\server.xml")) { Write-Host "[ERROR] Tomcat no instalado." ; return }
    $xml = [xml](Get-Content "$TOMCAT_HOME\conf\server.xml")
    $connector = $xml.Server.Service.Connector | Where-Object { $_.protocol -like "HTTP*" } | Select-Object -First 1
    Write-Host "  Puerto actual: $($connector.port)"
    $nuevo = Leer-Puerto
    $connector.port = "$nuevo"
    $xml.Save("$TOMCAT_HOME\conf\server.xml")
    $ver = (Get-Content "$TOMCAT_HOME\RELEASE-NOTES" -ErrorAction SilentlyContinue |
            Select-String "Apache Tomcat Version" | Select-Object -First 1).ToString().Split(" ")[-1]
    if (-not $ver) { $ver = "desconocida" }
    Remove-Item "$TOMCAT_HOME\webapps\ROOT\index.jsp" -Force -ErrorAction SilentlyContinue
    Crear-IndexHtml "Tomcat" $ver $nuevo "$TOMCAT_HOME\webapps\ROOT"
    Configurar-Firewall $nuevo "Tomcat HTTP"
    Reiniciar-Tomcat
}

# ─────────────────────────────────────────
#  NGINX
# ─────────────────────────────────────────

function Obtener-VersionesNginx {
    try {
        $html = Invoke-WebRequest -Uri "https://nginx.org/en/download.html" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $versiones = [regex]::Matches($html.Content, "nginx-(\d+\.\d+\.\d+)\.zip") |
                     ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique -Descending
        if ($versiones) { return $versiones }
    } catch {}
    return $null
}

function Configurar-NginxConf($puerto) {
    if (Test-Path $NGINX_CONF) { Copy-Item $NGINX_CONF "$NGINX_CONF.bak" -Force }
    $root = $NGINX_WEBROOT -replace '\\','/'
    $mime = "C:/nginx/conf/mime.types"
    $contenido = @"
worker_processes  1;
events { worker_connections 1024; }
http {
    server_tokens off;
    include       $mime;
    default_type  application/octet-stream;
    sendfile      off;
    keepalive_timeout 65;
    server {
        listen       $puerto;
        server_name  localhost;
        root         $root;
        index        index.html;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        autoindex off;
        location / { try_files `$uri `$uri/ =404; }
    }
}
"@
    [System.IO.File]::WriteAllText($NGINX_CONF, $contenido, [System.Text.UTF8Encoding]::new($false))
}

function Instalar-Nginx {
    if (-not (Verificar-Admin)) { return }

    $versiones = Obtener-VersionesNginx
    if (-not $versiones) { Write-Host "[ERROR] No se pudieron obtener versiones de Nginx." ; return }
    Write-Host ""
    Write-Host "  Versiones disponibles de Nginx:"
    for ($i = 0; $i -lt $versiones.Count; $i++) {
        Write-Host ("  {0,2}) {1}" -f ($i+1), $versiones[$i])
    }
    Write-Host ""
    $sel = $null
    while ($true) {
        $input = (Read-Host "  Opcion [1-$($versiones.Count)]").Trim()
        if ($input -match '^\d+$' -and [int]$input -ge 1 -and [int]$input -le $versiones.Count) {
            $sel = [int]$input - 1; break
        }
        Write-Host "[ERROR] Opcion invalida."
    }
    $versionElegida = $versiones[$sel]
    $puerto = Leer-Puerto

    $nginxZip = "$env:TEMP\nginx.zip"
    $url = "https://nginx.org/download/nginx-${versionElegida}.zip"
    Write-Host "  Descargando Nginx $versionElegida..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $nginxZip -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Descarga fallida."
        return
    }

    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    if (Test-Path "C:\nginx") { Remove-Item "C:\nginx" -Recurse -Force }
    Expand-Archive -Path $nginxZip -DestinationPath "C:\" -Force
    $extracted = Get-ChildItem "C:\" -Directory | Where-Object { $_.Name -like "nginx-*" } | Select-Object -First 1
    if ($extracted) { Rename-Item $extracted.FullName "C:\nginx" -Force }
    Remove-Item $nginxZip -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path "C:\nginx\nginx.exe")) { Write-Host "[ERROR] Instalacion fallida." ; return }

    if (-not (Test-Path $NGINX_WEBROOT)) { New-Item -ItemType Directory -Path $NGINX_WEBROOT -Force | Out-Null }
    Configurar-NginxConf $puerto
    Crear-IndexHtml "Nginx" $versionElegida $puerto $NGINX_WEBROOT
    Configurar-UsuarioDedicado "nginx_svc" $NGINX_WEBROOT

    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 1
    Start-Process -FilePath "C:\nginx\nginx.exe" -ArgumentList "-p C:\nginx" -WorkingDirectory "C:\nginx" -WindowStyle Hidden
    Start-Sleep 3
    Configurar-Firewall $puerto "Nginx HTTP"

    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($proc) { Write-Host "[OK] Nginx $versionElegida instalado y activo en el puerto $puerto." }
    else { Write-Host "[ERROR] Nginx no pudo iniciarse. Revisa: C:\nginx\logs\error.log" }
}

function Estado-Nginx {
    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($proc) { Write-Host "  Nginx en ejecucion (PID: $($proc[0].Id))." }
    else { Write-Host "  Nginx no esta en ejecucion." }
    if (Test-Path $NGINX_CONF) {
        $puerto = (Select-String -Path $NGINX_CONF -Pattern "listen\s+(\d+)" -ErrorAction SilentlyContinue)
        if ($puerto) {
            $p = $puerto.Matches[0].Groups[1].Value
            Write-Host "  Puerto configurado: $p"
            try { $r = Invoke-WebRequest "http://localhost:$p" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
                  Write-Host "  HTTP $($r.StatusCode) - Respondiendo correctamente." } catch {}
        }
    }
}

function Reiniciar-Nginx {
    if (-not (Verificar-Admin)) { return }
    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 1
    Start-Process -FilePath "C:\nginx\nginx.exe" -ArgumentList "-p C:\nginx" -WorkingDirectory "C:\nginx" -WindowStyle Hidden
    Start-Sleep 2
    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($proc) { Write-Host "[OK] Nginx reiniciado." }
    else { Write-Host "[ERROR] Nginx no pudo reiniciarse." }
}

function Reconfigurar-Nginx {
    if (-not (Verificar-Admin)) { return }
    if (-not (Test-Path "C:\nginx\nginx.exe")) { Write-Host "[ERROR] Nginx no instalado." ; return }
    $actual = (Select-String -Path $NGINX_CONF -Pattern "listen\s+(\d+)" -ErrorAction SilentlyContinue).Matches[0].Groups[1].Value
    Write-Host "  Puerto actual: $actual"
    $nuevo = Leer-Puerto
    $ver = (& "C:\nginx\nginx.exe" -v 2>&1).ToString().Split("/")[1].Trim()
    Configurar-NginxConf $nuevo
    Crear-IndexHtml "Nginx" $ver $nuevo $NGINX_WEBROOT
    Configurar-Firewall $nuevo "Nginx HTTP"
    Reiniciar-Nginx
    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($proc) { Write-Host "[OK] Nginx reconfigurado en el puerto $nuevo." }
    else { Write-Host "[ERROR] Nginx no pudo reiniciarse." }
}

#Requires -RunAsAdministrator
# ======================================================
#  SISTEMA DE APROVISIONAMIENTO WEB - WINDOWS
#  Practica 6 | PowerShell Automatizado - Script Unico
# ======================================================

# ─────────────────────────────────────────
#  VARIABLES GLOBALES
# ─────────────────────────────────────────
$APACHE_DIR     = "C:\Apache24"
$APACHE_WEBROOT = "C:\Apache24\htdocs"
$APACHE_CONF    = "C:\Apache24\conf\httpd.conf"
$NGINX_WEBROOT  = "C:\nginx\html"
$NGINX_CONF     = "C:\nginx\conf\nginx.conf"
$TOMCAT_HOME    = "C:\tomcat"
$IIS_WEBROOT    = "C:\inetpub\wwwroot"
$PUERTOS_RESERVADOS = @(21,22,23,25,53,67,68,110,143,161,443,445,3306,5432,8443)

# ─────────────────────────────────────────
#  FUNCIONES COMUNES
# ─────────────────────────────────────────

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
        $inp = (Read-Host "  Ingrese el puerto (ej. 80, 8080, 8888)").Trim()
        if (Validar-Puerto $inp) {
            Write-Host "  Puerto seleccionado: $inp"
            return [int]$inp
        }
    }
}

function Configurar-Firewall($puerto, $nombreRegla) {
    $existente = Get-NetFirewallRule -DisplayName $nombreRegla -ErrorAction SilentlyContinue
    if ($existente) { Remove-NetFirewallRule -DisplayName $nombreRegla -ErrorAction SilentlyContinue }
    New-NetFirewallRule -DisplayName $nombreRegla -Direction Inbound -Protocol TCP `
        -LocalPort $puerto -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  Firewall configurado. Puerto $puerto habilitado."
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
        $chars  = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%'
        $pwd    = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
        $secPwd = ConvertTo-SecureString $pwd -AsPlainText -Force
        New-LocalUser -Name $usuario -Password $secPwd -PasswordNeverExpires `
            -UserMayNotChangePassword -Description "Usuario dedicado servicio web" `
            -ErrorAction SilentlyContinue | Out-Null
    }
    if (-not (Test-Path $webroot)) { New-Item -ItemType Directory -Path $webroot -Force | Out-Null }
    $acl = Get-Acl $webroot
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
    $reglas = @(
        [System.Security.AccessControl.FileSystemAccessRule]::new("SYSTEM",        "FullControl",    "ContainerInherit,ObjectInherit", "None", "Allow"),
        [System.Security.AccessControl.FileSystemAccessRule]::new("Administrators", "FullControl",    "ContainerInherit,ObjectInherit", "None", "Allow"),
        [System.Security.AccessControl.FileSystemAccessRule]::new($usuario,         "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
    )
    foreach ($r in $reglas) { $acl.AddAccessRule($r) }
    Set-Acl -Path $webroot -AclObject $acl -ErrorAction SilentlyContinue
}

function Mostrar-Verificacion($nombreServicio, $puerto) {
    Write-Host ""
    Write-Host "  +------ Verificacion: $nombreServicio en puerto $puerto ------+"
    $svcName = $nombreServicio -replace '\s',''
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        $estado = if ($svc.Status -eq "Running") { "ACTIVO" } else { "INACTIVO" }
        Write-Host "  [$(if($svc.Status -eq 'Running'){'OK'}else{'!!'})] Servicio $svcName : $estado"
    }
    $conn = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $puerto }
    if ($conn) { Write-Host "  [OK] Puerto $puerto     : En escucha" }
    else        { Write-Host "  [??] Puerto $puerto     : No detectado aun" }
    Write-Host "  [>>] Encabezados HTTP (http://localhost:$puerto):"
    try {
        $r = Invoke-WebRequest "http://localhost:$puerto" -UseBasicParsing -TimeoutSec 4 -ErrorAction Stop
        Write-Host "       HTTP $($r.StatusCode) OK"
    } catch {
        Write-Host "       (Servicio aun iniciando o no responde)"
    }
    Write-Host "  +---------------------------------------------------+"
    Write-Host ""
    Read-Host "  Presiona ENTER para volver al menu"
}

# ─────────────────────────────────────────
#  IIS
# ─────────────────────────────────────────

function Instalar-IIS {
    Write-Host ""
    Write-Host "  ============================================"
    Write-Host "    Instalacion de IIS"
    Write-Host "  ============================================"
    $puerto = Leer-Puerto
    $confirm = Read-Host "  Confirmar instalacion de IIS en puerto $puerto [s/N]"
    if ($confirm -notmatch '^[sS]$') { Write-Host "  Cancelado." ; return }

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
    if ($binding) { Remove-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue }
    New-WebBinding -Name "Default Web Site" -Protocol http -Port $puerto -IPAddress "*" -ErrorAction SilentlyContinue | Out-Null

    $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if (-not $ver) { $ver = "IIS" }

    Crear-IndexHtml "IIS" $ver $puerto $IIS_WEBROOT
    Configurar-UsuarioDedicado "iis_svc" $IIS_WEBROOT

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

    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:httpProtocol "/-customHeaders.[name='X-Powered-By']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:httpProtocol "/+customHeaders.[name='X-Frame-Options',value='SAMEORIGIN']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:httpProtocol "/+customHeaders.[name='X-Content-Type-Options',value='nosniff']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:httpProtocol "/+customHeaders.[name='X-XSS-Protection',value='1; mode=block']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:requestFiltering "/+verbs.[verb='TRACE',allowed='false']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:requestFiltering "/+verbs.[verb='TRACK',allowed='false']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:requestFiltering "/+verbs.[verb='DELETE',allowed='false']" 2>&1 | Out-Null
    & "$env:windir\system32\inetsrv\appcmd.exe" set config /section:system.webServer/security/requestFiltering /removeServerHeader:true 2>&1 | Out-Null

    Write-Host "  Configurando firewall: abriendo puerto $puerto..."
    Configurar-Firewall $puerto "IIS HTTP"

    Start-Service W3SVC -ErrorAction SilentlyContinue
    Start-Sleep 2

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $pool = Get-Item "IIS:\AppPools\DefaultAppPool" -ErrorAction SilentlyContinue
    if ($pool -and $pool.state -ne "Started") {
        Start-WebItem "IIS:\AppPools\DefaultAppPool" -ErrorAction SilentlyContinue
        Start-Sleep 2
    }
    $site = Get-Item "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue
    if ($site -and $site.state -ne "Started") {
        Start-WebItem "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue
        Start-Sleep 1
    }

    $svc = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host ""
        Write-Host "  [OK] IIS instalado y asegurado."
        Write-Host "       Ruta web : $IIS_WEBROOT"
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' } | Select-Object -First 1).IPAddress
        Write-Host "       Accede en: http://${ip}:$puerto"
    } else {
        Write-Host "  [ERROR] IIS instalado pero no pudo iniciarse."
    }
    Mostrar-Verificacion "W3SVC" $puerto
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
        try {
            $r = Invoke-WebRequest "http://localhost:$puerto" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            Write-Host "  HTTP $($r.StatusCode) - Respondiendo correctamente."
        } catch { Write-Host "  No responde en http://localhost:$puerto" }
    }
}

function Reiniciar-IIS {
    & iisreset /restart 2>&1 | Out-Null
    Start-Sleep 3
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $pool = Get-Item "IIS:\AppPools\DefaultAppPool" -ErrorAction SilentlyContinue
    if ($pool -and $pool.state -ne "Started") { Start-WebItem "IIS:\AppPools\DefaultAppPool" -ErrorAction SilentlyContinue }
    $site = Get-Item "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue
    if ($site -and $site.state -ne "Started") { Start-WebItem "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue }
    $svc = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") { Write-Host "  [OK] IIS reiniciado." }
    else { Write-Host "  [ERROR] IIS no pudo reiniciarse." }
}

function Desinstalar-IIS {
    Write-Host "  Desinstalando IIS..."
    & iisreset /stop 2>&1 | Out-Null
    $features = @(
        "Web-Server","Web-Common-Http","Web-Default-Doc","Web-Static-Content",
        "Web-Http-Errors","Web-Http-Logging","Web-Stat-Compression","Web-Filtering",
        "Web-Mgmt-Tools","Web-Mgmt-Console","Web-Scripting-Tools"
    )
    Remove-WindowsFeature -Name $features -ErrorAction SilentlyContinue | Out-Null
    Remove-NetFirewallRule -DisplayName "IIS HTTP" -ErrorAction SilentlyContinue
    Write-Host "  [OK] IIS desinstalado."
}

# ─────────────────────────────────────────
#  APACHE
# ─────────────────────────────────────────

function Obtener-VersionApache {
    # Intentar obtener la ultima version desde Apache Lounge (distribucion Windows oficial)
    try {
        $html = Invoke-WebRequest -Uri "https://www.apachelounge.com/download/" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $match = [regex]::Match($html.Content, "httpd-(\d+\.\d+\.\d+)-win64")
        if ($match.Success) { return $match.Groups[1].Value }
    } catch {}
    return "2.4.63"  # fallback
}

function Instalar-Apache {
    Write-Host ""
    Write-Host "  ============================================"
    Write-Host "    Instalacion de Apache (httpd)"
    Write-Host "  ============================================"
    $puerto = Leer-Puerto
    $confirm = Read-Host "  Confirmar instalacion de Apache (httpd) en puerto $puerto [s/N]"
    if ($confirm -notmatch '^[sS]$') { Write-Host "  Cancelado." ; return }

    Write-Host "  Instalando Apache (descarga directa desde Apache Lounge)..."

    # Buscar version disponible
    $ver = Obtener-VersionApache
    Write-Host "  Version detectada: $ver"

    $tmpZip = "$env:TEMP\httpd.zip"
    $url    = "https://www.apachelounge.com/download/VS17/binaries/httpd-${ver}-win64-VS17.zip"

    Write-Host "  Descargando Apache $ver..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "  [WARN] Descarga principal fallida, intentando mirror..."
        try {
            $url2 = "https://github.com/nicksyosic/apache-windows/releases/latest/download/httpd-win64.zip"
            Invoke-WebRequest -Uri $url2 -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "  [ERROR] No se pudo descargar Apache. Verifica conexion a internet."
            return
        }
    }

    # Limpiar instalacion previa
    $apacheSvc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue
    if ($apacheSvc) {
        $apacheSvc | Stop-Service -Force -ErrorAction SilentlyContinue
        foreach ($s in $apacheSvc) {
            & sc.exe delete $s.Name 2>&1 | Out-Null
        }
    }
    if (Test-Path $APACHE_DIR) { Remove-Item $APACHE_DIR -Recurse -Force }

    Write-Host "  Extrayendo Apache..."
    Expand-Archive -Path $tmpZip -DestinationPath "$env:TEMP\apache_extract" -Force
    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue

    # El zip de Apache Lounge extrae como "Apache24"
    $extracted = Get-ChildItem "$env:TEMP\apache_extract" -Directory | Select-Object -First 1
    if (-not $extracted) {
        Write-Host "  [ERROR] Extraccion fallida."
        Remove-Item "$env:TEMP\apache_extract" -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
    Move-Item $extracted.FullName $APACHE_DIR -Force
    Remove-Item "$env:TEMP\apache_extract" -Recurse -Force -ErrorAction SilentlyContinue

    # Verificar que httpd.exe existe
    if (-not (Test-Path "$APACHE_DIR\bin\httpd.exe")) {
        Write-Host "  [ERROR] httpd.exe no encontrado en $APACHE_DIR\bin\"
        Write-Host "          Contenido de $APACHE_DIR\:"
        Get-ChildItem $APACHE_DIR | ForEach-Object { Write-Host "          $_" }
        return
    }

    Write-Host "  Configurando httpd.conf..."

    # Webroot especifico por puerto
    $webroot = "$APACHE_DIR\htdocs_$puerto"
    if (-not (Test-Path $webroot)) { New-Item -ItemType Directory -Path $webroot -Force | Out-Null }

    # Editar httpd.conf
    $confContent = Get-Content $APACHE_CONF -Raw
    $confContent = $confContent -replace "^Listen \d+", "Listen $puerto"
    $confContent = $confContent -replace "^#?Listen \d+", "Listen $puerto"
    $confContent = $confContent -replace "Listen 80", "Listen $puerto"
    $confContent = $confContent -replace "^ServerName .*", "ServerName localhost:$puerto"
    $confContent = $confContent -replace '#ServerName.*', "ServerName localhost:$puerto"
    $confContent = $confContent -replace 'DocumentRoot ".*"', "DocumentRoot `"$($webroot -replace '\\','/')`""
    $confContent = $confContent -replace '<Directory ".*Apache24.*htdocs.*">', "<Directory `"$($webroot -replace '\\','/')`">"
    $confContent = $confContent -replace 'ServerTokens Full', 'ServerTokens Prod'
    $confContent = $confContent -replace '#ServerTokens', 'ServerTokens Prod'
    [System.IO.File]::WriteAllText($APACHE_CONF, $confContent, [System.Text.UTF8Encoding]::new($false))

    # Archivo de seguridad extra
    $secDir = "$APACHE_DIR\conf\extra"
    if (-not (Test-Path $secDir)) { New-Item -ItemType Directory -Path $secDir -Force | Out-Null }
    $secConf = "$secDir\security.conf"
    $secContent = @"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
ServerSignature Off
TraceEnable Off
"@
    [System.IO.File]::WriteAllText($secConf, $secContent, [System.Text.UTF8Encoding]::new($false))

    # Incluir security.conf si no esta incluido
    $conf = Get-Content $APACHE_CONF -Raw
    if ($conf -notmatch "security.conf") {
        $conf += "`nInclude conf/extra/security.conf`n"
        [System.IO.File]::WriteAllText($APACHE_CONF, $conf, [System.Text.UTF8Encoding]::new($false))
    }

    # Obtener version real
    $verReal = (& "$APACHE_DIR\bin\httpd.exe" -v 2>&1 | Select-String "Apache/") 
    if ($verReal) { $verReal = ($verReal.ToString() -split "Apache/")[1].Split(" ")[0] }
    else { $verReal = $ver }

    Crear-IndexHtml "Apache" $verReal $puerto $webroot
    Configurar-UsuarioDedicado "apache_svc" $webroot

    # Instalar como servicio Windows
    $svcName = "Apache$puerto"
    Write-Host "  Registrando servicio Windows: $svcName..."
    & "$APACHE_DIR\bin\httpd.exe" -k install -n $svcName 2>&1 | Out-Null

    # Iniciar servicio
    Start-Sleep 1
    Start-Service $svcName -ErrorAction SilentlyContinue
    Start-Sleep 3

    Write-Host "  Configurando firewall: abriendo puerto $puerto..."
    Configurar-Firewall $puerto "Apache HTTP $puerto"

    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host ""
        Write-Host "  [OK] Apache instalado y asegurado."
        Write-Host "       Ruta web : $webroot"
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' } | Select-Object -First 1).IPAddress
        Write-Host "       Accede en: http://${ip}:$puerto"
    } else {
        Write-Host "  [ERROR] Apache instalado pero no pudo iniciarse."
        Write-Host "          Revisa: $APACHE_DIR\logs\error.log"
    }
    Mostrar-Verificacion $svcName $puerto
}

function Estado-Apache {
    $svcs = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue
    if (-not $svcs) { Write-Host "  Apache no esta instalado como servicio." ; return }
    foreach ($s in $svcs) {
        Write-Host "  Servicio $($s.Name) - Estado: $($s.Status)"
    }
    if (Test-Path $APACHE_CONF) {
        $listen = (Select-String -Path $APACHE_CONF -Pattern "^Listen (\d+)" -ErrorAction SilentlyContinue)
        if ($listen) {
            $p = $listen.Matches[0].Groups[1].Value
            Write-Host "  Puerto configurado: $p"
            try {
                $r = Invoke-WebRequest "http://localhost:$p" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
                Write-Host "  HTTP $($r.StatusCode) - Respondiendo correctamente."
            } catch { Write-Host "  No responde en http://localhost:$p" }
        }
    }
}

function Reiniciar-Apache {
    $svcs = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue
    if (-not $svcs) { Write-Host "  [ERROR] Apache no instalado." ; return }
    foreach ($s in $svcs) {
        Restart-Service $s.Name -ErrorAction SilentlyContinue
        Start-Sleep 2
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") { Write-Host "  [OK] $($s.Name) reiniciado." }
        else { Write-Host "  [ERROR] $($s.Name) no pudo reiniciarse." }
    }
}

function Desinstalar-Apache {
    Write-Host "  Desinstalando Apache..."
    $svcs = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue
    foreach ($s in $svcs) {
        Stop-Service $s.Name -Force -ErrorAction SilentlyContinue
        & "$APACHE_DIR\bin\httpd.exe" -k uninstall -n $s.Name 2>&1 | Out-Null
        & sc.exe delete $s.Name 2>&1 | Out-Null
    }
    if (Test-Path $APACHE_DIR) { Remove-Item $APACHE_DIR -Recurse -Force }
    Remove-NetFirewallRule -DisplayName "Apache HTTP*" -ErrorAction SilentlyContinue
    Write-Host "  [OK] Apache desinstalado."
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
    return @("1.26.3","1.24.0")
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
    Write-Host ""
    Write-Host "  ============================================"
    Write-Host "    Instalacion de Nginx"
    Write-Host "  ============================================"

    $versiones = Obtener-VersionesNginx
    Write-Host ""
    Write-Host "  Versiones disponibles de Nginx:"
    for ($i = 0; $i -lt $versiones.Count; $i++) {
        Write-Host ("  {0,2}) {1}" -f ($i+1), $versiones[$i])
    }
    Write-Host ""
    $sel = $null
    while ($true) {
        $inp = (Read-Host "  Opcion [1-$($versiones.Count)]").Trim()
        if ($inp -match '^\d+$' -and [int]$inp -ge 1 -and [int]$inp -le $versiones.Count) {
            $sel = [int]$inp - 1; break
        }
        Write-Host "  [ERROR] Opcion invalida."
    }
    $versionElegida = $versiones[$sel]
    $puerto = Leer-Puerto
    $confirm = Read-Host "  Confirmar instalacion de Nginx $versionElegida en puerto $puerto [s/N]"
    if ($confirm -notmatch '^[sS]$') { Write-Host "  Cancelado." ; return }

    $nginxZip = "$env:TEMP\nginx.zip"
    $url = "https://nginx.org/download/nginx-${versionElegida}.zip"
    Write-Host "  Descargando Nginx $versionElegida..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $nginxZip -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] Descarga fallida."
        return
    }

    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    if (Test-Path "C:\nginx") { Remove-Item "C:\nginx" -Recurse -Force }
    Expand-Archive -Path $nginxZip -DestinationPath "C:\" -Force
    $extracted = Get-ChildItem "C:\" -Directory | Where-Object { $_.Name -like "nginx-*" } | Select-Object -First 1
    if ($extracted) { Rename-Item $extracted.FullName "C:\nginx" -Force }
    Remove-Item $nginxZip -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path "C:\nginx\nginx.exe")) { Write-Host "  [ERROR] Instalacion fallida." ; return }

    if (-not (Test-Path $NGINX_WEBROOT)) { New-Item -ItemType Directory -Path $NGINX_WEBROOT -Force | Out-Null }
    Configurar-NginxConf $puerto
    Crear-IndexHtml "Nginx" $versionElegida $puerto $NGINX_WEBROOT
    Configurar-UsuarioDedicado "nginx_svc" $NGINX_WEBROOT

    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 1
    Start-Process -FilePath "C:\nginx\nginx.exe" -ArgumentList "-p C:\nginx" -WorkingDirectory "C:\nginx" -WindowStyle Hidden
    Start-Sleep 3

    Write-Host "  Configurando firewall: abriendo puerto $puerto..."
    Configurar-Firewall $puerto "Nginx HTTP"

    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host ""
        Write-Host "  [OK] Nginx $versionElegida instalado y asegurado."
        Write-Host "       Ruta web : $NGINX_WEBROOT"
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' } | Select-Object -First 1).IPAddress
        Write-Host "       Accede en: http://${ip}:$puerto"
    } else {
        Write-Host "  [ERROR] Nginx no pudo iniciarse. Revisa: C:\nginx\logs\error.log"
    }
    Mostrar-Verificacion "nginx" $puerto
}

function Estado-Nginx {
    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($proc) { Write-Host "  Nginx en ejecucion (PID: $($proc[0].Id))." }
    else { Write-Host "  Nginx no esta en ejecucion." }
    if (Test-Path $NGINX_CONF) {
        $listen = (Select-String -Path $NGINX_CONF -Pattern "listen\s+(\d+)" -ErrorAction SilentlyContinue)
        if ($listen) {
            $p = $listen.Matches[0].Groups[1].Value
            Write-Host "  Puerto configurado: $p"
            try {
                $r = Invoke-WebRequest "http://localhost:$p" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
                Write-Host "  HTTP $($r.StatusCode) - Respondiendo correctamente."
            } catch { Write-Host "  No responde en http://localhost:$p" }
        }
    }
}

function Reiniciar-Nginx {
    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 1
    Start-Process -FilePath "C:\nginx\nginx.exe" -ArgumentList "-p C:\nginx" -WorkingDirectory "C:\nginx" -WindowStyle Hidden
    Start-Sleep 2
    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($proc) { Write-Host "  [OK] Nginx reiniciado." }
    else { Write-Host "  [ERROR] Nginx no pudo reiniciarse." }
}

function Desinstalar-Nginx {
    Write-Host "  Desinstalando Nginx..."
    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 1
    if (Test-Path "C:\nginx") { Remove-Item "C:\nginx" -Recurse -Force }
    Remove-NetFirewallRule -DisplayName "Nginx HTTP" -ErrorAction SilentlyContinue
    Write-Host "  [OK] Nginx desinstalado."
}

# ─────────────────────────────────────────
#  TOMCAT
# ─────────────────────────────────────────

function Obtener-VersionesTomcat {
    $ramas     = @(9, 10, 11)
    $etiquetas = @{9="LTS"; 10="Latest"; 11="Desarrollo"}
    $resultado = @()
    foreach ($rama in $ramas) {
        $fallback = @{9="9.0.98"; 10="10.1.34"; 11="11.0.2"}
        try {
            $html   = Invoke-WebRequest -Uri "https://downloads.apache.org/tomcat/tomcat-${rama}/" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            $ultima = ($html.Links.href | Where-Object { $_ -match '^v[\d\.]+/$' } | Sort-Object | Select-Object -Last 1).TrimEnd('/').TrimStart('v')
            if (-not $ultima) { $ultima = $fallback[$rama] }
        } catch { $ultima = $fallback[$rama] }
        $resultado += [PSCustomObject]@{ Rama=$rama; Version=$ultima; Etiqueta=$etiquetas[$rama] }
    }
    return $resultado
}

function Instalar-Tomcat {
    Write-Host ""
    Write-Host "  ============================================"
    Write-Host "    Instalacion de Tomcat"
    Write-Host "  ============================================"
    Write-Host ""
    Write-Host "  Versiones disponibles de Tomcat:"
    $versiones = Obtener-VersionesTomcat
    for ($i = 0; $i -lt $versiones.Count; $i++) {
        Write-Host ("  {0,2}) Tomcat {1} {2} ({3})" -f ($i+1), $versiones[$i].Rama, $versiones[$i].Etiqueta, $versiones[$i].Version)
    }
    Write-Host ""
    $sel = $null
    while ($true) {
        $inp = (Read-Host "  Opcion [1-3]").Trim()
        if ($inp -match '^[123]$') { $sel = [int]$inp - 1; break }
        Write-Host "  [ERROR] Elige 1, 2 o 3."
    }
    $rama   = $versiones[$sel].Rama
    $ver    = $versiones[$sel].Version
    $puerto = Leer-Puerto
    $confirm = Read-Host "  Confirmar instalacion de Tomcat $ver en puerto $puerto [s/N]"
    if ($confirm -notmatch '^[sS]$') { Write-Host "  Cancelado." ; return }

    # Java
    $javaOk = $false
    try { & java -version 2>&1 | Out-Null; $javaOk = $true } catch {}
    if (-not $javaOk) {
        $jdkDir = Get-ChildItem "C:\jdk17" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $jdkDir) {
            $javaExe = Get-ChildItem "C:\Program Files\" -Recurse -Filter "java.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($javaExe) { $jdkDir = [PSCustomObject]@{ FullName = $javaExe.DirectoryName -replace "\\bin$","" } }
        }
        if ($jdkDir) {
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
            } catch { Write-Host "  [ERROR] No se pudo instalar Java." ; return }
        }
    }

    $url    = "https://downloads.apache.org/tomcat/tomcat-${rama}/v${ver}/bin/apache-tomcat-${ver}.zip"
    $tmpZip = "$env:TEMP\tomcat.zip"
    Write-Host "  Descargando Tomcat $ver..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop
    } catch { Write-Host "  [ERROR] Descarga fallida." ; return }

    if (Test-Path $TOMCAT_HOME) { Remove-Item $TOMCAT_HOME -Recurse -Force }
    Expand-Archive -Path $tmpZip -DestinationPath "C:\" -Force
    $extracted = Get-ChildItem "C:\" -Directory | Where-Object { $_.Name -like "apache-tomcat-*" } | Select-Object -First 1
    if ($extracted) { Rename-Item $extracted.FullName $TOMCAT_HOME }
    Remove-Item $tmpZip -Force

    if (-not (Test-Path "$TOMCAT_HOME\bin\catalina.bat")) { Write-Host "  [ERROR] Instalacion de Tomcat fallida." ; return }

    $serverXml = "$TOMCAT_HOME\conf\server.xml"
    (Get-Content $serverXml) -replace 'port="8080"', "port=`"$puerto`"" |
        ForEach-Object { $_ -replace 'protocol="HTTP/1\.1"', 'protocol="HTTP/1.1" server="Tomcat" xpoweredBy="false"' } |
        Set-Content $serverXml -Encoding UTF8

    Remove-Item "$TOMCAT_HOME\webapps\ROOT\index.jsp" -Force -ErrorAction SilentlyContinue
    Crear-IndexHtml "Tomcat" $ver $puerto "$TOMCAT_HOME\webapps\ROOT"
    Configurar-UsuarioDedicado "tomcat_svc" "$TOMCAT_HOME\webapps"

    $webXml = "$TOMCAT_HOME\conf\web.xml"
    if (Test-Path $webXml) {
        $contenido = Get-Content $webXml -Raw
        if ($contenido -notmatch "HttpHeaderSecurityFilter") {
            $contenido = $contenido -replace '</web-app>', '<filter><filter-name>httpHeaderSecurity</filter-name><filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class><init-param><param-name>antiClickJackingEnabled</param-name><param-value>true</param-value></init-param></filter><filter-mapping><filter-name>httpHeaderSecurity</filter-name><url-pattern>/*</url-pattern></filter-mapping></web-app>'
        }
        [System.IO.File]::WriteAllText($webXml, $contenido, [System.Text.UTF8Encoding]::new($false))
    }

    $javaHome = $env:JAVA_HOME
    if (-not $javaHome) { $javaHome = (Get-Command java -ErrorAction SilentlyContinue).Source -replace '\\bin\\java.exe','' }
    $env:JAVA_HOME     = $javaHome
    $env:CATALINA_HOME = $TOMCAT_HOME
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$TOMCAT_HOME\bin\catalina.bat`" start" `
        -WorkingDirectory "$TOMCAT_HOME\bin" -WindowStyle Hidden -ErrorAction SilentlyContinue
    Start-Sleep 10

    Write-Host "  Configurando firewall: abriendo puerto $puerto..."
    Configurar-Firewall $puerto "Tomcat HTTP"

    try {
        Invoke-WebRequest "http://localhost:$puerto" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop | Out-Null
        Write-Host ""
        Write-Host "  [OK] Tomcat $ver instalado y activo en el puerto $puerto."
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' } | Select-Object -First 1).IPAddress
        Write-Host "       Accede en: http://${ip}:$puerto"
    } catch {
        Write-Host "  [ERROR] Tomcat instalado pero no responde."
        Write-Host "          Revisa: $TOMCAT_HOME\logs\catalina.out"
    }
    Mostrar-Verificacion "Tomcat" $puerto
}

function Estado-Tomcat {
    $proc = Get-Process -Name "java" -ErrorAction SilentlyContinue
    if ($proc) { Write-Host "  Tomcat corriendo (PID: $($proc[0].Id))." }
    else { Write-Host "  Tomcat no esta en ejecucion." }
    if (Test-Path "$TOMCAT_HOME\conf\server.xml") {
        $puerto = ([xml](Get-Content "$TOMCAT_HOME\conf\server.xml")).Server.Service.Connector |
                  Where-Object { $_.protocol -like "HTTP*" } | Select-Object -First 1 -ExpandProperty port
        if ($puerto) {
            Write-Host "  Puerto configurado: $puerto"
            try {
                $r = Invoke-WebRequest "http://localhost:$puerto" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
                Write-Host "  HTTP $($r.StatusCode) - Respondiendo correctamente."
            } catch { Write-Host "  No responde en http://localhost:$puerto" }
        }
    }
}

function Reiniciar-Tomcat {
    Get-Process -Name "java" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 2
    $env:CATALINA_HOME = $TOMCAT_HOME
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$TOMCAT_HOME\bin\catalina.bat`" start" `
        -WorkingDirectory "$TOMCAT_HOME\bin" -WindowStyle Hidden -ErrorAction SilentlyContinue
    Start-Sleep 10
    $proc = Get-Process -Name "java" -ErrorAction SilentlyContinue
    if ($proc) { Write-Host "  [OK] Tomcat reiniciado." }
    else { Write-Host "  [ERROR] Tomcat no pudo reiniciarse." }
}

function Desinstalar-Tomcat {
    Write-Host "  Desinstalando Tomcat..."
    Get-Process -Name "java" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 2
    if (Test-Path $TOMCAT_HOME) { Remove-Item $TOMCAT_HOME -Recurse -Force }
    Remove-NetFirewallRule -DisplayName "Tomcat HTTP" -ErrorAction SilentlyContinue
    Write-Host "  [OK] Tomcat desinstalado."
}

# ─────────────────────────────────────────
#  VERIFICAR SERVICIOS ACTIVOS
# ─────────────────────────────────────────

function Verificar-Servicios {
    Write-Host ""
    Write-Host "  ============================================"
    Write-Host "    Estado de todos los servidores web"
    Write-Host "  ============================================"
    Write-Host ""
    Write-Host "  --- IIS ---"
    Estado-IIS
    Write-Host ""
    Write-Host "  --- Apache ---"
    Estado-Apache
    Write-Host ""
    Write-Host "  --- Nginx ---"
    Estado-Nginx
    Write-Host ""
    Write-Host "  --- Tomcat ---"
    Estado-Tomcat
    Write-Host ""
    Read-Host "  Presiona ENTER para volver al menu"
}

# ─────────────────────────────────────────
#  LIMPIAR TODO
# ─────────────────────────────────────────

function Limpiar-Todo {
    $confirm = Read-Host "  [ADVERTENCIA] Esto desinstalara IIS, Apache, Nginx y Tomcat. Confirmar [s/N]"
    if ($confirm -notmatch '^[sS]$') { Write-Host "  Cancelado." ; return }
    Desinstalar-IIS
    Desinstalar-Apache
    Desinstalar-Nginx
    Desinstalar-Tomcat
    Write-Host ""
    Write-Host "  [OK] Entorno limpiado."
    Read-Host "  Presiona ENTER para volver al menu"
}

# ─────────────────────────────────────────
#  MENU PRINCIPAL
# ─────────────────────────────────────────

while ($true) {
    Clear-Host
    $ip     = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' } | Select-Object -First 1).IPAddress
    $os     = (Get-WmiObject Win32_OperatingSystem).Caption
    $fecha  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    Write-Host "  +======================================================+"
    Write-Host "  |     SISTEMA DE APROVISIONAMIENTO WEB - WINDOWS      |"
    Write-Host "  |           Practica 6 | PowerShell Automatizado       |"
    Write-Host "  +======================================================+"
    Write-Host "  |  Sistema : $os"
    Write-Host "  |  IP      : $ip"
    Write-Host "  |  Fecha   : $fecha"
    Write-Host "  +======================================================+"
    Write-Host ""
    Write-Host "  +-----------------------------------------+"
    Write-Host "  |        SELECCIONA UNA OPCION             |"
    Write-Host "  +-----------------------------------------+"
    Write-Host "  |  1) Instalar IIS                         |"
    Write-Host "  |  2) Instalar Apache (httpd)              |"
    Write-Host "  |  3) Instalar Nginx                       |"
    Write-Host "  |  4) Instalar Tomcat                      |"
    Write-Host "  |  5) Verificar servicio activo            |"
    Write-Host "  |  6) Desinstalar servidor especifico      |"
    Write-Host "  |  7) Levantar/Reiniciar servicio          |"
    Write-Host "  |  8) Limpiar entorno (purgar todo)        |"
    Write-Host "  |  0) Salir                                |"
    Write-Host "  +-----------------------------------------+"
    Write-Host ""
    $OPT = (Read-Host "  Opcion").Trim()

    switch ($OPT) {
        "1" { Instalar-IIS }
        "2" { Instalar-Apache }
        "3" { Instalar-Nginx }
        "4" { Instalar-Tomcat }
        "5" { Verificar-Servicios }
        "6" {
            Write-Host ""
            Write-Host "  Que servidor deseas desinstalar?"
            Write-Host "  1) IIS   2) Apache   3) Nginx   4) Tomcat"
            $sub = (Read-Host "  Opcion").Trim()
            switch ($sub) {
                "1" { Desinstalar-IIS }
                "2" { Desinstalar-Apache }
                "3" { Desinstalar-Nginx }
                "4" { Desinstalar-Tomcat }
                default { Write-Host "  Opcion invalida." }
            }
            Read-Host "  Presiona ENTER para volver al menu"
        }
        "7" {
            Write-Host ""
            Write-Host "  Que servidor deseas reiniciar?"
            Write-Host "  1) IIS   2) Apache   3) Nginx   4) Tomcat"
            $sub = (Read-Host "  Opcion").Trim()
            switch ($sub) {
                "1" { Reiniciar-IIS }
                "2" { Reiniciar-Apache }
                "3" { Reiniciar-Nginx }
                "4" { Reiniciar-Tomcat }
                default { Write-Host "  Opcion invalida." }
            }
            Read-Host "  Presiona ENTER para volver al menu"
        }
        "8" { Limpiar-Todo }
        "0" {
            Write-Host ""
            Write-Host "  Saliendo... Hasta luego!"
            Write-Host ""
            exit 0
        }
        default {
            Write-Host "  [WARN] Opcion invalida."
            Start-Sleep -Seconds 1
        }
    }
}

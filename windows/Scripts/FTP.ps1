$V = "Green"
$R = "Red"
$A = "Cyan"

function Preparar-Entorno-FTP {
    if (!(Get-WindowsFeature Web-Ftp-Server).Installed) {
        Install-WindowsFeature Web-Ftp-Server, Web-Mgmt-Console, Web-Scripting-Tools
    }

    $basePath = "C:\inetpub\ftproot"
    $rutas = @("$basePath\LocalUser", "C:\FTP_Data\publico", "C:\FTP_Data\grupos\reprobados", "C:\FTP_Data\grupos\recursadores")
    foreach ($ruta in $rutas) {
        if (!(Test-Path $ruta)) { New-Item -ItemType Directory -Path $ruta -Force | Out-Null }
    }

    $grupos = @("reprobados", "recursadores", "grupo-ftp")
    foreach ($g in $grupos) {
        if (!(Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $g | Out-Null }
    }

    # Desactivar complejidad de contraseñas localmente para la práctica
    & secedit /export /cfg c:\sec.cfg | Out-Null
    (Get-Content c:\sec.cfg) -replace 'PasswordComplexity = 1', 'PasswordComplexity = 0' | Set-Content c:\sec.cfg
    & secedit /configure /db $env:windir\security\local.sdb /cfg c:\sec.cfg /areas SECURITYPOLICY | Out-Null

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Stop-Service ftpsvc -ErrorAction SilentlyContinue

    if (!(Test-Path "IIS:\Sites\GestorFTP")) {
        New-WebFtpSite -Name "GestorFTP" -Port 21 -PhysicalPath $basePath -Force
        Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.userIsolation.mode -Value "IsolateDirectory"
    }

    # PARCHE SSL: Permitir conexiones sin cifrado (Evita error 534)
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"

    & {
        try {
            Add-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\Sites\GestorFTP" -Name "." -Value @{accessType="Allow";users="anonymous";permissions="Read"} -ErrorAction SilentlyContinue
        } catch { }
    }

    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "Entorno Windows FTP listo (Políticas de seguridad ajustadas)" -ForegroundColor $V
}

function Eliminar-Todo {
    Write-Host "`nIniciando limpieza total..." -ForegroundColor $R
    Import-Module WebAdministration
    $usuarios = Get-LocalGroupMember -Group "grupo-ftp" -ErrorAction SilentlyContinue
    
    foreach ($u in $usuarios) {
        $name = $u.Name.Split('\')[-1]
        Remove-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$name" -ErrorAction SilentlyContinue
        Remove-LocalUser -Name $name -Force -ErrorAction SilentlyContinue
        $rutaFisica = "C:\inetpub\ftproot\LocalUser\$name"
        if (Test-Path $rutaFisica) { Remove-Item -Path $rutaFisica -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Host "[-] Usuario y datos de $name eliminados." -ForegroundColor $R
    }
    Write-Host "Limpieza completada." -ForegroundColor $V
}

function Establecer-Permisos-NTFS {
    param($u, $g)
    $h = "C:\inetpub\ftproot\LocalUser\$u"
    if (!(Test-Path $h)) { New-Item -ItemType Directory -Path $h -Force | Out-Null }
    icacls $h /grant "${u}:(OI)(CI)F" /inheritance:r | Out-Null
    icacls "C:\FTP_Data\grupos\$g" /grant "${g}:(OI)(CI)M" | Out-Null
    icacls "C:\FTP_Data\publico" /grant "grupo-ftp:(OI)(CI)M" | Out-Null
}

function Dar-Alta-Usuario {
    param($u, $p, $g)
    if (!(Get-LocalUser -Name $u -ErrorAction SilentlyContinue)) {
        $sec = ConvertTo-SecureString $p -AsPlainText -Force
        try {
            New-LocalUser -Name $u -Password $sec -AccountNeverExpires -ErrorAction Stop | Out-Null
            Add-LocalGroupMember -Group "grupo-ftp" -Member $u -ErrorAction SilentlyContinue
            Add-LocalGroupMember -Group $g -Member $u -ErrorAction SilentlyContinue
        } catch {
            Write-Host "[!] Error al crear $u. Verifique políticas de Windows." -ForegroundColor $R
            return
        }
    }

    Establecer-Permisos-NTFS -u $u -g $g
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/general" -PhysicalPath "C:\FTP_Data\publico" -Force | Out-Null
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/$g" -PhysicalPath "C:\FTP_Data\grupos\$g" -Force | Out-Null
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/$u" -PhysicalPath "C:\inetpub\ftproot\LocalUser\$u" -Force | Out-Null
    Write-Host "Usuario $u configurado correctamente." -ForegroundColor $V
}

function Mostrar-Resumen-Usuarios {
    Write-Host "`n--- USUARIOS FTP ACTIVOS ---" -ForegroundColor $A
    $miembros = Get-LocalGroupMember -Group "grupo-ftp" -ErrorAction SilentlyContinue
    if (!$miembros) { Write-Host "No hay usuarios registrados." ; return }
    Write-Host ("{0,-15} | {1,-15}" -f "USUARIO", "GRUPO")
    Write-Host "---------------------------------"
    foreach ($m in $miembros) {
        $u = $m.Name.Split('\')[-1]
        $gr = "Sin grupo"
        if (Get-LocalGroupMember -Group "reprobados" | Where-Object {$_.Name -eq $m.Name}) { $gr = "reprobados" }
        elseif (Get-LocalGroupMember -Group "recursadores" | Where-Object {$_.Name -eq $m.Name}) { $gr = "recursadores" }
        Write-Host ("{0,-15} | {1,-15}" -f $u, $gr)
    }
}

function Diagnostico-Sistema {
    Write-Host "`n--- ESTADO DEL SERVIDOR ---" -ForegroundColor $A
    Write-Host "Servicio FTP: $((Get-Service ftpsvc).Status)"
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"}).IPAddress | Select-Object -First 1
    Write-Host "IP del Servidor: $ip"
    if (Get-Website | Where-Object {$_.Name -eq "GestorFTP"}) { Write-Host "Sitio IIS GestorFTP: OK" } else { Write-Host "Sitio IIS: ERROR" -ForegroundColor $R }
}

function Menu-Principal {
    Preparar-Entorno-FTP
    while ($true) {
        Write-Host "`n=======================================" -ForegroundColor $A
        Write-Host "      GESTOR FTP WINDOWS "
        Write-Host "=======================================" -ForegroundColor $A
        Write-Host "1) Registro masivo"
        Write-Host "2) Ver usuarios"
        Write-Host "3) Diagnostico"
        Write-Host "4) Limpiar sistema (Borrar todo)"
        Write-Host "0) Salir"
        $o = Read-Host "Opcion"
        switch ($o) {
            "1" {
                $total = Read-Host "Cantidad"
                for ($i=1; $i -le $total; $i++) {
                    $un = Read-Host "User"
                    $up = Read-Host "Pass"
                    $ug = Read-Host "Grupo (1:reprobados, 2:recursadores)"
                    $grp = if ($ug -eq "1") { "reprobados" } else { "recursadores" }
                    Dar-Alta-Usuario -u $un -p $up -g $grp
                }
            }
            "2" { Mostrar-Resumen-Usuarios }
            "3" { Diagnostico-Sistema }
            "4" { Eliminar-Todo }
            "0" { exit }
        }
    }
}

Menu-Principal

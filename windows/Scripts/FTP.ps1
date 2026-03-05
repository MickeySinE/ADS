$V = "Green"; $R = "Red"; $A = "Cyan"

function Preparar-Entorno-FTP {
    Write-Host "Configurando Roles de IIS y FTP..." -ForegroundColor $A
    Install-WindowsFeature Web-Mgmt-Console, Web-FTP-Server, Web-FTP-Service -ErrorAction SilentlyContinue
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $basePaths = @("C:\FTP_Data\publico", "C:\FTP_Data\grupos\reprobados", "C:\FTP_Data\grupos\recursadores", "C:\inetpub\ftproot\LocalUser")
    foreach ($path in $basePaths) {
        if (!(Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }

    if (!(Test-Path "IIS:\Sites\GestorFTP")) {
        New-WebFtpSite -Name "GestorFTP" -Port 21 -PhysicalPath "C:\inetpub\ftproot" -Force | Out-Null
    }

    Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/basicAuthentication" -Name "enabled" -Value $true -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'GestorFTP'
    Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value $true -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'GestorFTP'

    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.userIsolation.mode -Value "IsolateUsers"

    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
    
    if (!(Get-LocalGroup -Name "grupo-ftp" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "grupo-ftp" }
    if (!(Get-LocalGroup -Name "reprobados" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "reprobados" }
    if (!(Get-LocalGroup -Name "recursadores" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "recursadores" }

    Add-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" -Name "." -Value @{accessType='Allow';users='anonymous';permissions='Read'} -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'GestorFTP' -ErrorAction SilentlyContinue

    icacls "C:\inetpub\ftproot" /grant "IUSR:(OI)(CI)(R)" /T | Out-Null
    icacls "C:\inetpub\ftproot" /grant "Everyone:(OI)(CI)(R)" /T | Out-Null

    Restart-Service ftpsvc
    Write-Host "Entorno FTP Listo y Autenticación Básica Habilitada." -ForegroundColor $V
}

function Dar-Alta-Usuario {
    param($u, $p, $g)
    
    if (!(Get-LocalUser -Name $u -ErrorAction SilentlyContinue)) {
        $sec = ConvertTo-SecureString $p -AsPlainText -Force
        try {
            New-LocalUser -Name $u -Password $sec -AccountNeverExpires -ErrorAction Stop | Out-Null
            Add-LocalGroupMember -Group "grupo-ftp" -Member $u
            Add-LocalGroupMember -Group $g -Member $u
        } catch {
            Write-Host "[!] Error: La contraseña no cumple los requisitos (usa Mayúscula, Número y Punto)." -ForegroundColor $R
            return
        }
    }

    $uRoot = "C:\inetpub\ftproot\LocalUser\$u"
    if (!(Test-Path $uRoot)) { New-Item -ItemType Directory -Path $uRoot -Force | Out-Null }

    icacls $uRoot /grant "${u}:(OI)(CI)F" /inheritance:r | Out-Null

    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/general" -PhysicalPath "C:\FTP_Data\publico" -Force | Out-Null
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/$g" -PhysicalPath "C:\FTP_Data\grupos\$g" -Force | Out-Null

    Add-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" -Name "." -Value @{accessType='Allow';users=$u;permissions='Read, Write'} -PSPath 'MACHINE/WEBROOT/APPHOST' -Location "GestorFTP" -ErrorAction SilentlyContinue

    Write-Host "[+] Usuario $u configurado con acceso al grupo $g." -ForegroundColor $V
}

function Eliminar-Todo {
    Write-Host "`nIniciando limpieza del sistema..." -ForegroundColor $R
    $miembros = Get-LocalGroupMember -Group "grupo-ftp" -ErrorAction SilentlyContinue
    foreach ($m in $miembros) {
        $u = $m.Name.Split('\')[-1]
        Remove-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u" -ErrorAction SilentlyContinue
        Remove-LocalUser -Name $u -ErrorAction SilentlyContinue
        $rutaFisica = "C:\inetpub\ftproot\LocalUser\$u"
        if (Test-Path $rutaFisica) { Remove-Item -Path $rutaFisica -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Host "[-] Borrado: $u" -ForegroundColor $R
    }
    Write-Host "Limpieza completada." -ForegroundColor $V
}

function Menu-Principal {
    Preparar-Entorno-FTP
    while ($true) {
        Write-Host "`n--- GESTOR FTP WINDOWS ---" -ForegroundColor $A
        Write-Host "1) Registro masivo"
        Write-Host "2) Ver usuarios"
        Write-Host "3) Diagnostico"
        Write-Host "4) Limpiar sistema"
        Write-Host "0) Salir"
        $o = Read-Host "Seleccione una opción"
        switch ($o) {
            "1" {
                $un = Read-Host "Nombre de Usuario"
                $up = Read-Host "Contraseña (Ej: TemporaL.2026)"
                $ug = Read-Host "Grupo (1:reprobados, 2:recursadores)"
                $grp = if ($ug -eq "1") { "reprobados" } else { "recursadores" }
                Dar-Alta-Usuario -u $un -p $up -g $grp
            }
            "2" { Get-LocalGroupMember -Group "grupo-ftp" -ErrorAction SilentlyContinue | Select Name -Unique }
            "3" { Write-Host "Estado FTPSVC: $((Get-Service ftpsvc).Status)" -ForegroundColor $V }
            "4" { Eliminar-Todo }
            "0" { exit }
        }
    }
}

# Ejecutar el programa
Menu-Principal

$V = "Green"; $R = "Red"; $A = "Cyan"

function Preparar-Entorno-FTP {
    if (!(Get-WindowsFeature Web-Ftp-Server).Installed) {
        Install-WindowsFeature Web-Ftp-Server, Web-Mgmt-Console, Web-Scripting-Tools -IncludeManagementTools | Out-Null
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

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    
    if (!(Test-Path "IIS:\Sites\GestorFTP")) {
        New-WebFtpSite -Name "GestorFTP" -Port 21 -PhysicalPath $basePath -Force | Out-Null
        Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.userIsolation.mode -Value "IsolateDirectory"
    }

    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"

    Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/anonymousAuthentication" -PSPath "IIS:\Sites\GestorFTP" -Name "enabled" -Value $true -ErrorAction SilentlyContinue

    try {
        Add-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\Sites\GestorFTP" -Name "." -Value @{accessType="Allow";users="anonymous";permissions="Read"} -ErrorAction SilentlyContinue
    } catch { }

    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "Entorno Windows FTP listo (Anónimo Habilitado)" -ForegroundColor $V
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
            Write-Host "[!] Error: La contraseña de $u no cumple requisitos (usa Mayúscula, Número y Punto)." -ForegroundColor $R
            return
        }
    }

    $uPath = "C:\inetpub\ftproot\LocalUser\$u"
    if (!(Test-Path $uPath)) { New-Item -ItemType Directory -Path $uPath -Force | Out-Null }

    icacls $uPath /grant "${u}:(OI)(CI)F" /inheritance:r | Out-Null
    
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/general" -PhysicalPath "C:\FTP_Data\publico" -Force | Out-Null
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/$g" -PhysicalPath "C:\FTP_Data\grupos\$g" -Force | Out-Null
    
    Write-Host "[+] Usuario $u configurado." -ForegroundColor $V
}

function Eliminar-Todo {
    Write-Host "`nIniciando limpieza..." -ForegroundColor $R
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
        Write-Host "1) Registro masivo`n2) Ver usuarios`n3) Diagnostico`n4) Limpiar sistema`0) Salir"
        $o = Read-Host "Opcion"
        switch ($o) {
            "1" {
                $un = Read-Host "User"; $up = Read-Host "Pass"; $ug = Read-Host "Grupo (1:reprobados, 2:recursadores)"
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
Menu-Principal

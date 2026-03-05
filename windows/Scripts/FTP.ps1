$V = "Green"; $R = "Red"; $A = "Cyan"

function Preparar-Entorno-FTP {
    Install-WindowsFeature Web-Mgmt-Console, Web-FTP-Server, Web-FTP-Service -ErrorAction SilentlyContinue
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $basePaths = @("C:\FTP_Data\publico", "C:\FTP_Data\grupos\reprobados", "C:\FTP_Data\grupos\recursadores", "C:\inetpub\ftproot\LocalUser")
    foreach ($path in $basePaths) {
        if (!(Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }

    if (!(Test-Path "IIS:\Sites\GestorFTP")) {
        New-WebFtpSite -Name "GestorFTP" -Port 21 -PhysicalPath "C:\inetpub\ftproot" -Force | Out-Null
    }

    # Configuración de Autenticación y Aislamiento
    Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/basicAuthentication" -Name "enabled" -Value $true -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP"
    Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value $true -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP"
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.userIsolation.mode -Value 2 # 2 = IsolateUsers
    
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
    
    # Autorización Total
    Clear-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP" -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" -Name "." -Value @{accessType='Allow';users='*';permissions='Read,Write'} -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP"

    # Permisos NTFS (Lectura en la raíz es VITAL)
    icacls "C:\inetpub\ftproot" /grant "*S-1-1-0:(R)" /T | Out-Null

    if (!(Get-LocalGroup -Name "reprobados" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "reprobados" }
    if (!(Get-LocalGroup -Name "recursadores" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "recursadores" }

    Restart-Service ftpsvc -Force
    Write-Host "Entorno FTP corregido." -ForegroundColor $V
}

function Dar-Alta-Usuario {
    param($u, $p, $g)
    $sec = ConvertTo-SecureString $p -AsPlainText -Force
    
    if (!(Get-LocalUser -Name $u -ErrorAction SilentlyContinue)) {
        try {
            New-LocalUser -Name $u -Password $sec -AccountNeverExpires -ErrorAction Stop | Out-Null
            Add-LocalGroupMember -Group "Usuarios" -Member $u -ErrorAction SilentlyContinue
            Add-LocalGroupMember -Group $g -Member $u -ErrorAction SilentlyContinue
            
            # --- SOLUCIÓN AL 530: Permitir inicio de sesión local ---
            # Esto agrega al usuario al derecho de logon local si el servidor es estricto
            net localgroup "Usuarios de escritorio remoto" $u /add 2>$null
        } catch {
            Write-Host "[!] Error de contraseña." -ForegroundColor $R
            return
        }
    }

    $uRoot = "C:\inetpub\ftproot\LocalUser\$u"
    if (!(Test-Path $uRoot)) { New-Item -ItemType Directory -Path $uRoot -Force | Out-Null }
    
    # Permisos en su carpeta
    icacls $uRoot /grant "${u}:(OI)(CI)F" /inheritance:r | Out-Null

    # Virtual Directories
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/general" -PhysicalPath "C:\FTP_Data\publico" -Force | Out-Null
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/$g" -PhysicalPath "C:\FTP_Data\grupos\$g" -Force | Out-Null

    Write-Host "[+] Usuario $u listo. Prueba el login ahora." -ForegroundColor $V
}

function Menu-Principal {
    Preparar-Entorno-FTP
    while ($true) {
        Write-Host "`n--- GESTOR FTP WINDOWS ---" -ForegroundColor $A
        Write-Host "1) Registro masivo`n2) Ver usuarios`n3) Cambiar de grupo`n4) Eliminar usuario`n5) Diagnostico`n0) Salir"
        $o = Read-Host "Opcion"
        switch ($o) {
            "1" {
                $un = Read-Host "User"; $up = Read-Host "Pass"; $ug = Read-Host "Grupo (1 o 2)"
                $grp = if ($ug -eq "1") { "reprobados" } else { "recursadores" }
                Dar-Alta-Usuario -u $un -p $up -g $grp
            }
            "2" { Get-LocalUser | Where-Object {$_.Enabled} | Select Name }
            "3" {
                $un = Read-Host "User"; $ug = Read-Host "Nuevo Grupo (1 o 2)"
                $grp = if ($ug -eq "1") { "reprobados" } else { "recursadores" }
                # Aquí llamarías a la función de cambio de grupo de la respuesta anterior
            }
            "4" {
                $un = Read-Host "User a eliminar"
                if (Get-LocalUser -Name $un -ErrorAction SilentlyContinue) {
                    Remove-LocalUser -Name $un -Confirm:$false
                    Write-Host "Usuario eliminado." -ForegroundColor $R
                }
            }
            "5" { Write-Host "Estado FTPSVC: $((Get-Service ftpsvc).Status)" -ForegroundColor $V }
            "0" { exit }
        }
    }
}
Menu-Principal

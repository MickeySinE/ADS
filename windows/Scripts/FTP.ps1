$V = "Green"; $R = "Red"; $A = "Cyan"

function Preparar-Entorno-FTP {
    Write-Host "Configurando Seguridad y Roles..." -ForegroundColor $A
    Install-WindowsFeature Web-Mgmt-Console, Web-FTP-Server, Web-FTP-Service -ErrorAction SilentlyContinue
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $basePaths = @("C:\FTP_Data\publico", "C:\FTP_Data\grupos\reprobados", "C:\FTP_Data\grupos\recursadores", "C:\inetpub\ftproot\LocalUser")
    foreach ($path in $basePaths) {
        if (!(Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }

    if (!(Test-Path "IIS:\Sites\GestorFTP")) {
        New-WebFtpSite -Name "GestorFTP" -Port 21 -PhysicalPath "C:\inetpub\ftproot" -Force | Out-Null
    }

    # --- PARCHE DE AUTENTICACION ---
    Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/basicAuthentication" -Name "enabled" -Value $true -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP"
    Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value $true -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP"
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.userIsolation.mode -Value 2
    
    # Autorización Total
    Clear-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP" -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" -Name "." -Value @{accessType='Allow';users='*';permissions='Read,Write'} -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP"

    # --- PARCHE DE SEGURIDAD LOCAL (Logon Locally) ---
    $secFile = "C:\Windows\Temp\sec.inf"
    secedit /export /cfg $secFile /areas USER_RIGHTS | Out-Null
    if ((Get-Content $secFile) -notmatch "SeInteractiveLogonRight.*\*S-1-5-32-545") {
        (Get-Content $secFile) -replace "SeInteractiveLogonRight =", "SeInteractiveLogonRight = *S-1-5-32-545," | Out-File $secFile -Encoding ascii
        secedit /configure /db "C:\Windows\Temp\sec.sdb" /cfg $secFile /areas USER_RIGHTS | Out-Null
    }

    icacls "C:\inetpub\ftproot" /grant "*S-1-1-0:(R)" /T | Out-Null
    Restart-Service ftpsvc -Force
    Write-Host "Entorno FTP Listo y Desbloqueado." -ForegroundColor $V
}

function Dar-Alta-Usuario {
    param($u, $p, $g)
    $sec = ConvertTo-SecureString $p -AsPlainText -Force
    if (!(Get-LocalUser -Name $u -ErrorAction SilentlyContinue)) {
        try {
            New-LocalUser -Name $u -Password $sec -AccountNeverExpires -ErrorAction Stop | Out-Null
            Add-LocalGroupMember -Group "Usuarios" -Member $u -ErrorAction SilentlyContinue
            if (!(Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $g }
            Add-LocalGroupMember -Group $g -Member $u -ErrorAction SilentlyContinue
        } catch {
            Write-Host "[!] Error de complejidad de contraseña." -ForegroundColor $R
            return
        }
    }
    $uRoot = "C:\inetpub\ftproot\LocalUser\$u"
    if (!(Test-Path $uRoot)) { New-Item -ItemType Directory -Path $uRoot -Force | Out-Null }
    icacls $uRoot /grant "${u}:(OI)(CI)F" /inheritance:r | Out-Null
    
    # Directorios Virtuales
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/general" -PhysicalPath "C:\FTP_Data\publico" -Force | Out-Null
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/$g" -PhysicalPath "C:\FTP_Data\grupos\$g" -Force | Out-Null
    
    Write-Host "[+] Usuario $u creado y carpetas vinculadas." -ForegroundColor $V
}

function Cambiar-Grupo-Usuario {
    param($u, $gNuevo)
    if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) {
        Remove-LocalGroupMember -Group "reprobados" -Member $u -ErrorAction SilentlyContinue
        Remove-LocalGroupMember -Group "recursadores" -Member $u -ErrorAction SilentlyContinue
        if (!(Get-LocalGroup -Name $gNuevo -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $gNuevo }
        Add-LocalGroupMember -Group $gNuevo -Member $u
        
        # Actualizar Directorio Virtual
        Remove-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/reprobados" -ErrorAction SilentlyContinue
        Remove-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/recursadores" -ErrorAction SilentlyContinue
        New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/$gNuevo" -PhysicalPath "C:\FTP_Data\grupos\$gNuevo" -Force | Out-Null
        
        Write-Host "[+] Usuario $u movido a $gNuevo." -ForegroundColor $V
    } else { Write-Host "[!] Usuario no encontrado." -ForegroundColor $R }
}

function Eliminar-Usuario {
    param($u)
    if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $u -Confirm:$false
        $uRoot = "C:\inetpub\ftproot\LocalUser\$u"
        if (Test-Path $uRoot) { Remove-Item -Path $uRoot -Recurse -Force }
        # Quitar directorios virtuales de IIS
        Remove-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u" -ErrorAction SilentlyContinue
        Write-Host "[-] Usuario $u y sus carpetas eliminados." -ForegroundColor $R
    } else { Write-Host "[!] El usuario no existe." -ForegroundColor $R }
}

function Menu-Principal {
    Preparar-Entorno-FTP
    while ($true) {
        Write-Host "`n--- GESTOR FTP COMPLETO ---" -ForegroundColor $A
        Write-Host "1) Crear Usuario`n2) Ver Usuarios`n3) Cambiar Grupo`n4) Eliminar Usuario`n5) Diagnostico`n0) Salir"
        $o = Read-Host "Seleccione Opcion"
        switch ($o) {
            "1" {
                $un = Read-Host "User"; $up = Read-Host "Pass (Ej: Admin.1234)"; $ug = Read-Host "Grupo (1:reprobados, 2:recursadores)"
                $grp = if ($ug -eq "1") { "reprobados" } else { "recursadores" }
                Dar-Alta-Usuario -u $un -p $up -g $grp
            }
            "2" { Get-LocalUser | Where-Object {$_.Enabled} | Select Name, Description }
            "3" {
                $un = Read-Host "User"; $ug = Read-Host "Nuevo Grupo (1:reprobados, 2:recursadores)"
                $grp = if ($ug -eq "1") { "reprobados" } else { "recursadores" }
                Cambiar-Grupo-Usuario -u $un -gNuevo $grp
            }
            "4" { $un = Read-Host "User a eliminar"; Eliminar-Usuario -u $un }
            "5" { 
                Write-Host "Servicio FTP: $((Get-Service ftpsvc).Status)"
                Write-Host "Sitio GestorFTP: $((Get-FtpSite -Name GestorFTP).State)"
            }
            "0" { exit }
        }
    }
}
Menu-Principal

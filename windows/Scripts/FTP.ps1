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

    Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/basicAuthentication" -Name "enabled" -Value $true -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP"
    Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/anonymousAuthentication" -Name "enabled" -Value $true -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP"
    
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.userIsolation.mode -Value "IsolateUsers"
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
    
    Clear-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP" -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" -Name "." -Value @{accessType='Allow';users='*';permissions='Read,Write'} -PSPath "MACHINE/WEBROOT/APPHOST" -Location "GestorFTP"

    icacls "C:\inetpub\ftproot" /grant "*S-1-1-0:(R)" /T | Out-Null

    if (!(Get-LocalGroup -Name "reprobados" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "reprobados" }
    if (!(Get-LocalGroup -Name "recursadores" -ErrorAction SilentlyContinue)) { New-LocalGroup -Name "recursadores" }

    Restart-Service ftpsvc -Force
    Write-Host "Entorno FTP Listo." -ForegroundColor $V
}

function Dar-Alta-Usuario {
    param($u, $p, $g)
    $sec = ConvertTo-SecureString $p -AsPlainText -Force
    
    if (!(Get-LocalUser -Name $u -ErrorAction SilentlyContinue)) {
        try {
            New-LocalUser -Name $u -Password $sec -AccountNeverExpires -ErrorAction Stop | Out-Null
            Add-LocalGroupMember -Group "Usuarios" -Member $u -ErrorAction SilentlyContinue
            Add-LocalGroupMember -Group $g -Member $u -ErrorAction SilentlyContinue
        } catch {
            Write-Host "[!] Error de complejidad de contraseña." -ForegroundColor $R
            return
        }
    }

    $uRoot = "C:\inetpub\ftproot\LocalUser\$u"
    if (!(Test-Path $uRoot)) { New-Item -ItemType Directory -Path $uRoot -Force | Out-Null }
    
    icacls $uRoot /grant "${u}:(OI)(CI)F" /inheritance:r | Out-Null

    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/general" -PhysicalPath "C:\FTP_Data\publico" -Force | Out-Null
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/$g" -PhysicalPath "C:\FTP_Data\grupos\$g" -Force | Out-Null

    Write-Host "[+] Usuario $u configurado. Intenta loguear ahora." -ForegroundColor $V
}

function Cambiar-Grupo-Usuario {
    param($u, $gNuevo)
    if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) {
        Remove-LocalGroupMember -Group "reprobados" -Member $u -ErrorAction SilentlyContinue
        Remove-LocalGroupMember -Group "recursadores" -Member $u -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group $gNuevo -Member $u
        
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
        Write-Host "[-] Usuario $u eliminado." -ForegroundColor $R
    } else { Write-Host "[!] El usuario no existe." -ForegroundColor $R }
}

function Menu-Principal {
    Preparar-Entorno-FTP
    while ($true) {
        Write-Host "`n--- GESTOR FTP WINDOWS ---" -ForegroundColor $A
        Write-Host "1) Registro masivo`n2) Ver usuarios`n3) Cambiar de grupo`n4) Eliminar usuario`n5) Diagnostico`n0) Salir"
        $o = Read-Host "Opcion"
        switch ($o) {
            "1" {
                $un = Read-Host "User"; $up = Read-Host "Pass"; $ug = Read-Host "Grupo (1:reprobados, 2:recursadores)"
                $grp = if ($ug -eq "1") { "reprobados" } else { "recursadores" }
                Dar-Alta-Usuario -u $un -p $up -g $grp
            }
            "2" { Get-LocalUser | Where-Object {$_.Enabled} | Select Name }
            "3" {
                $un = Read-Host "User"; $ug = Read-Host "Nuevo Grupo (1:reprobados, 2:recursadores)"
                $grp = if ($ug -eq "1") { "reprobados" } else { "recursadores" }
                Cambiar-Grupo-Usuario -u $un -gNuevo $grp
            }
            "4" {
                $un = Read-Host "User a eliminar"
                Eliminar-Usuario -u $un
            }
            "5" { Write-Host "Estado FTPSVC: $((Get-Service ftpsvc).Status)" -ForegroundColor $V }
            "0" { exit }
        }
    }
}
Menu-Principal

$ErrorActionPreference = "SilentlyContinue"

function Preparar-EntornoFTP {
    Install-WindowsFeature Web-Server, Web-Ftp-Server, Web-Mgmt-Console -IncludeManagementTools

    $ftpSite = "ServidorFTP"
    $basePath = "C:\inetpub\ftproot"
    $gruposPath = "$basePath\grupos"
    
    if (!(Test-Path $basePath)) { New-Item -Path $basePath -ItemType Directory }
    if (!(Test-Path "$basePath\general")) { New-Item -Path "$basePath\general" -ItemType Directory }
    if (!(Test-Path "$gruposPath\reprobados")) { New-Item -Path "$gruposPath\reprobados" -Force -ItemType Directory }
    if (!(Test-Path "$gruposPath\recursadores")) { New-Item -Path "$gruposPath\recursadores" -Force -ItemType Directory }
    if (!(Test-Path "$basePath\usuarios")) { New-Item -Path "$basePath\usuarios" -ItemType Directory }

    if (!(Get-WebFtpSite -Name $ftpSite)) {
        New-WebFtpSite -Name $ftpSite -Port 21 -PhysicalPath $basePath
    }

    Set-ItemProperty "IIS:\Sites\ServidorFTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\ServidorFTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\ServidorFTP" -Name ftpServer.directoryBrowse.showFlags -Value "VirtualDirectories"

    Add-WebConfiguration "/system.ftpServer/security/authorization" -value @{accessType="Allow";users="anonymous";permissions="Read"} -PSPath IIS:\ -location $ftpSite
    
    if (!([ADSI]"WinNT://./reprobados,group")) { net localgroup reprobados /add }
    if (!([ADSI]"WinNT://./recursadores,group")) { net localgroup recursadores /add }
    if (!([ADSI]"WinNT://./grupo-ftp,group")) { net localgroup grupo-ftp /add }

    icacls "$basePath\general" /grant "grupo-ftp:(OI)(CI)M" /inheritance:e
    icacls "$basePath\general" /grant "Anonymous Logon:R"

    Restart-Service ftpsvc
}

function Configurar-EstructuraUsuario($usuario, $grupo) {
    $userPath = "C:\inetpub\ftproot\usuarios\$usuario"
    if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory }

    icacls $userPath /grant "${usuario}:(OI)(CI)F" /inheritance:r
    
    $sitePath = "IIS:\Sites\ServidorFTP"
    New-WebVirtualDirectory -Site "ServidorFTP" -Name "$usuario/general" -PhysicalPath "C:\inetpub\ftproot\general"
    New-WebVirtualDirectory -Site "ServidorFTP" -Name "$usuario/$grupo" -PhysicalPath "C:\inetpub\ftproot\grupos\$grupo"
    New-WebVirtualDirectory -Site "ServidorFTP" -Name "$usuario/$usuario" -PhysicalPath $userPath

    Add-WebConfiguration "/system.ftpServer/security/authorization" -value @{accessType="Allow";users=$usuario;permissions="Read,Write"} -PSPath IIS:\ -location "ServidorFTP/$usuario"
}

function Dar-AltaUsuario($user, $pass, $group) {
    net user $user $pass /add /passwordchg:no
    net localgroup grupo-ftp $user /add
    net localgroup $group $user /add
    
    Configurar-EstructuraUsuario $user $group
    Write-Host "[✓] Usuario $user configurado." -ForegroundColor Green
}

function Mover-UsuarioGrupo($user, $nGroup) {
    net localgroup reprobados $user /delete
    net localgroup recursadores $user /delete
    net localgroup $nGroup $user /add

    Remove-WebVirtualDirectory -Site "ServidorFTP" -Name "$user/reprobados"
    Remove-WebVirtualDirectory -Site "ServidorFTP" -Name "$user/recursadores"
    
    New-WebVirtualDirectory -Site "ServidorFTP" -Name "$user/$nGroup" -PhysicalPath "C:\inetpub\ftproot\grupos\$nGroup"
    Write-Host "[✓] Cambio de grupo aplicado." -ForegroundColor Green
}

function Menu-Principal {
    Preparar-EntornoFTP
    while ($true) {
        Clear-Host
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "      GESTOR FTP WINDOWS SERVER"
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "1) Registro masivo"
        Write-Host "2) Cambiar grupo"
        Write-Host "0) Salir"
        $opt = Read-Host "Opción"

        switch ($opt) {
            "1" {
                $total = Read-Host "Cantidad de usuarios"
                for ($i=1; $i -le $total; $i++) {
                    $u_name = Read-Host "Username"
                    $u_pass = Read-Host "Password"
                    $g_opt = Read-Host "Grupo (1:reprobados, 2:recursadores)"
                    $grp = if ($g_opt -eq "1") { "reprobados" } else { "recursadores" }
                    Dar-AltaUsuario $u_name $u_pass $grp
                }
            }
            "2" {
                $u_name = Read-Host "Usuario"
                $g_opt = Read-Host "Nuevo Grupo (1:reprobados, 2:recursadores)"
                $grp = if ($g_opt -eq "1") { "reprobados" } else { "recursadores" }
                Mover-UsuarioGrupo $u_name $grp
            }
            "0" { exit }
        }
        Read-Host "Presione Enter para continuar"
    }
}

Menu-Principal

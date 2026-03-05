$VERDE = "Green"
$ROJO = "Red"
$AZUL = "Cyan"

function Preparar-Entorno-FTP {
    if (!(Get-WindowsFeature Web-Ftp-Server).Installed) {
        Install-WindowsFeature Web-Ftp-Server, Web-Mgmt-Console
    }

    $basePath = "C:\inetpub\ftproot"
    $rutas = @(
        "$basePath\LocalUser",
        "C:\FTP_Data\publico",
        "C:\FTP_Data\grupos\reprobados",
        "C:\FTP_Data\grupos\recursadores"
    )
    foreach ($ruta in $rutas) {
        if (!(Test-Path $ruta)) { New-Item -ItemType Directory -Path $ruta -Force | Out-Null }
    }

    $grupos = @("reprobados", "recursadores", "grupo-ftp")
    foreach ($g in $grupos) {
        if (!(Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $g | Out-Null
        }
    }

    Import-Module WebAdministration
    if (!(Test-Path "IIS:\Sites\GestorFTP")) {
        New-WebFtpSite -Name "GestorFTP" -Port 21 -PhysicalPath $basePath -Force
        Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.userIsolation.mode -Value "IsolateDirectory"
    }

    $anonPath = "$basePath\LocalUser\public"
    if (!(Test-Path $anonPath)) { New-Item -ItemType Directory -Path $anonPath -Force | Out-Null }
    
    Add-WebConfigurationRule -Filter "/system.ftpServer/security/authorization" -PSPath "IIS:\Sites\GestorFTP" -Value @{accessType="Allow";users="anonymous";permissions="Read"}
    
    Write-Host "[✓] Entorno Windows FTP preparado." -ForegroundColor $VERDE
}

function Establecer-Permisos-NTFS {
    param($usuario, $grupo)
    $homeUsuario = "C:\inetpub\ftproot\LocalUser\$usuario"
    
    if (!(Test-Path $homeUsuario)) { New-Item -ItemType Directory -Path $homeUsuario -Force | Out-Null }

    icacls $homeUsuario /grant "${usuario}:(OI)(CI)F" /inheritance:r | Out-Null
    icacls "C:\FTP_Data\grupos\$grupo" /grant "${grupo}:(OI)(CI)M" | Out-Null
    icacls "C:\FTP_Data\publico" /grant "grupo-ftp:(OI)(CI)M" | Out-Null
}

function Dar-Alta-Usuario {
    param($user, $pass, $group)

    if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
        Write-Host "[!] El usuario $user ya existe." -ForegroundColor $ROJO
        return
    }

    $password = ConvertTo-SecureString $pass -AsPlainText -Force
    New-LocalUser -Name $user -Password $password -AccountNeverExpires | Out-Null
    
    Add-LocalGroupMember -Group "grupo-ftp" -Member $user
    Add-LocalGroupMember -Group $group -Member $user

    Establecer-Permisos-NTFS -usuario $user -grupo $group

    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$user/general" -PhysicalPath "C:\FTP_Data\publico"
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$user/$group" -PhysicalPath "C:\FTP_Data\grupos\$group"
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$user/$user" -PhysicalPath "C:\inetpub\ftproot\LocalUser\$user"
    
    Write-Host "[✓] Usuario $user configurado." -ForegroundColor $VERDE
}

function Mover-Usuario-Grupo {
    param($user, $n_group)

    if (!(Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) {
        Write-Host "[!] Usuario no encontrado." -ForegroundColor $ROJO
        return
    }

    $viejos = @("reprobados", "recursadores")
    foreach ($v in $viejos) { 
        Remove-LocalGroupMember -Group $v -Member $user -ErrorAction SilentlyContinue 
        Remove-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$user/$v" -ErrorAction SilentlyContinue
    }

    Add-LocalGroupMember -Group $n_group -Member $user
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$user/$n_group" -PhysicalPath "C:\FTP_Data\grupos\$n_group"
    
    Write-Host "[✓] Cambio de grupo aplicado." -ForegroundColor $VERDE
}

function Menu-Principal {
    Preparar-Entorno-FTP
    
    while ($true) {
        Write-Host "`n=======================================" -ForegroundColor $AZUL
        Write-Host "      GESTOR FTP WINDOWS (IIS)"
        Write-Host "=======================================" -ForegroundColor $AZUL
        Write-Host "1) Registro masivo"
        Write-Host "2) Cambiar grupo"
        Write-Host "3) Diagnóstico"
        Write-Host "0) Salir"
        $opt = Read-Host "Opción"

        switch ($opt) {
            "1" {
                $total = Read-Host "Cantidad"
                for ($i=1; $i -le $total; $i++) {
                    $u = Read-Host "Username"
                    $p = Read-Host "Password" -AsSecureString
                    $g = Read-Host "Grupo (1:reprobados, 2:recursadores)"
                    $grp = if ($g -eq "1") { "reprobados" } else { "recursadores" }
                    $pText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))
                    Dar-Alta-Usuario -user $u -pass $pText -group $grp
                }
            }
            "2" {
                $u = Read-Host "Usuario"
                $g = Read-Host "Nuevo Grupo (1:reprobados, 2:recursadores)"
                $grp = if ($g -eq "1") { "reprobados" } else { "recursadores" }
                Mover-Usuario-Grupo -user $u -n_group $grp
            }
            "3" {
                Get-Service ftpsvc | Select-Object Name, Status
                Get-LocalUser | Select-Object Name, Enabled
            }
            "0" { exit }
        }
    }
}

Menu-Principal

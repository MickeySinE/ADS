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

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Stop-Service ftpsvc -ErrorAction SilentlyContinue

    if (!(Test-Path "IIS:\Sites\GestorFTP")) {
        New-WebFtpSite -Name "GestorFTP" -Port 21 -PhysicalPath $basePath -Force
        Set-ItemProperty "IIS:\Sites\GestorFTP" -Name ftpServer.userIsolation.mode -Value "IsolateDirectory"
    }

    & {
        $filter = "/system.ftpServer/security/authorization"
        try {
            Add-WebConfigurationProperty -Filter $filter -PSPath "IIS:\Sites\GestorFTP" -Name "." -Value @{accessType="Allow";users="anonymous";permissions="Read"} -ErrorAction SilentlyContinue
        } catch { }
    }

    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "Entorno Windows FTP listo (Aislamiento configurado)" -ForegroundColor $V
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
    if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) { return }
    $sec = ConvertTo-SecureString $p -AsPlainText -Force
    New-LocalUser -Name $u -Password $sec -AccountNeverExpires | Out-Null
    Add-LocalGroupMember -Group "grupo-ftp" -Member $u
    Add-LocalGroupMember -Group $g -Member $u
    Establecer-Permisos-NTFS -u $u -g $g
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/general" -PhysicalPath "C:\FTP_Data\publico"
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/$g" -PhysicalPath "C:\FTP_Data\grupos\$g"
    New-WebVirtualDirectory -Site "GestorFTP" -Name "LocalUser/$u/$u" -PhysicalPath "C:\inetpub\ftproot\LocalUser\$u"
    Write-Host "Usuario $u creado" -ForegroundColor $V
}

function Menu-Principal {
    Preparar-Entorno-FTP
    while ($true) {
        Write-Host "--- GESTOR FTP ---" -ForegroundColor $A
        Write-Host "1. Registro"
        Write-Host "2. Diagnostico"
        Write-Host "0. Salir"
        $o = Read-Host "Opcion"
        if ($o -eq "1") {
            $un = Read-Host "User"
            $up = Read-Host "Pass"
            $ug = Read-Host "Grupo (1:reprobados, 2:recursadores)"
            $grp = if ($ug -eq "1") { "reprobados" } else { "recursadores" }
            Dar-Alta-Usuario -u $un -p $up -g $grp
        }
        elseif ($o -eq "2") {
            Get-Service ftpsvc | Select Status
            Get-LocalUser | Select Name
        }
        elseif ($o -eq "0") { break }
    }
}

Menu-Principal

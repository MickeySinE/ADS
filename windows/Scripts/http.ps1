# ─────────────────────────────────────────
#  MENÚ PRINCIPAL
# ─────────────────────────────────────────

function Mostrar-Menu {
    Clear-Host
    Write-Host "================================================"
    Write-Host "       Administrador de Servidores HTTP"
    Write-Host "================================================"
    Write-Host ""
    Write-Host "  [IIS]"
    Write-Host "   1) Instalar IIS"
    Write-Host "   2) Estado IIS"
    Write-Host "   3) Reiniciar IIS"
    Write-Host "   4) Reconfigurar IIS"
    Write-Host ""
    Write-Host "  [Tomcat]"
    Write-Host "   5) Instalar Tomcat"
    Write-Host "   6) Estado Tomcat"
    Write-Host "   7) Reiniciar Tomcat"
    Write-Host "   8) Reconfigurar Tomcat"
    Write-Host ""
    Write-Host "  [Nginx]"
    Write-Host "   9) Instalar Nginx"
    Write-Host "  10) Estado Nginx"
    Write-Host "  11) Reiniciar Nginx"
    Write-Host "  12) Reconfigurar Nginx"
    Write-Host ""
    Write-Host "   0) Salir"
    Write-Host ""
}

do {
    Mostrar-Menu
    $opcion = (Read-Host "  Elige una opcion").Trim()
    switch ($opcion) {
        "1"  { Instalar-IIS }
        "2"  { Estado-IIS }
        "3"  { Reiniciar-IIS }
        "4"  { Reconfigurar-IIS }
        "5"  { Instalar-Tomcat }
        "6"  { Estado-Tomcat }
        "7"  { Reiniciar-Tomcat }
        "8"  { Reconfigurar-Tomcat }
        "9"  { Instalar-Nginx }
        "10" { Estado-Nginx }
        "11" { Reiniciar-Nginx }
        "12" { Reconfigurar-Nginx }
        "0"  { Write-Host "  Hasta luego." ; break }
        default { Write-Host "[ERROR] Opcion invalida." }
    }
    if ($opcion -ne "0") { Read-Host "`n  Presiona Enter para continuar" }
} while ($opcion -ne "0")

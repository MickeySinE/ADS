#!/bin/bash

validar_ip() {
    local ip=$1
    # Valida formato X.X.X.X y que no sean las prohibidas
    if [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        if [[ $ip != "0.0.0.0" && $ip != "255.255.255.255" ]]; then
            return 0 # Es válida
        fi
    fi
    return 1 # No es válida
}

while true; do
    clear  # <--- Esto limpia la pantalla para que no se vea amontonado
    echo "==============================="
    echo "       MENU DHCP FEDORA        "
    echo "==============================="
    echo "1) Instalar/Verificar"
    echo "2) Configurar Ambito"
    echo "3) Monitorear"
    echo "4) Salir"
    read -p "Seleccione: " opt

    case $opt in
        2)
            read -p "Nombre del Ambito: " NAME
            while true; do
                read -p "IP Inicial (ej. 192.168.100.50): " START
                validar_ip "$START" && break
                echo "IP no valida, intenta de nuevo."
            done
            while true; do
                read -p "IP Final (ej. 192.168.100.150): " END
                validar_ip "$END" && break
                echo "IP no valida, intenta de nuevo."
            done
            # ... resto del codigo ...
            echo "Presiona Enter para continuar..."
            read
            ;;
        4) exit 0 ;;
    esac
done

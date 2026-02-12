#!/bin/bash

validar_ip() {
    local ip=$1
    if [[ $ip == "0.0.0.0" || $ip == "255.255.255.255" || $ip == "127.0.0.1" ]]; then
        return 1
    fi
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octetos <<< "$ip"
        for octeto in "${octetos[@]}"; do
            if [[ $octeto -lt 0 || $octeto -gt 255 ]]; then return 1; fi
        done
        return 0
    fi
    return 1
}

ip_a_numero() {
    local ip=$1
    IFS='.' read -r a b c d <<< "$ip"
    echo "$(( (a << 24) + (b << 16) + (c << 8) + d ))"
}

while true; do
    clear
    echo " ----- DHCP FEDORA SERVER ----- "
    echo "1) Verificar estado"
    echo "2) Instalar/Desinstalar"
    echo "3) Configurar Ambito"
    echo "4) Ver Leases"
    echo "5) Limpiar/Eliminar Leases"
    echo "6) Salir"
    echo ""
    read -p "Seleccione una opcion: " opcion
    
    case $opcion in
        "1")
            if systemctl is-active --quiet dhcpd; then
                echo -e "\e[32m\nEstado del servicio: ACTIVO\e[0m"
            else
                echo -e "\e[31m\nEstado del servicio: INACTIVO o ERROR\e[0m"
                sudo journalctl -u dhcpd -n 5 --no-pager
            fi
            read -p "Presione Enter..."
            ;;
        "2")
            echo "Escriba 'I' para Instalar o 'D' para Desinstalar"
            read accion
            if [[ ${accion^^} == 'I' ]]; then
                sudo dnf install -y dhcp-server
            elif [[ ${accion^^} == 'D' ]]; then
                sudo dnf remove -y dhcp-server
            fi
            read -p "Presione Enter..."
            ;;
       "3")
            if ! rpm -q dhcp-server &> /dev/null; then
                echo -e "\e[31mError: Instale el rol primero.\e[0m"
                read -p "Presione Enter..."
                continue
            fi
            
            read -p "Nombre del nuevo Ambito: " nombreAmbito
            read -p "IP del Servidor (ej. 10.0.0.4): " ipServer
            validar_ip "$ipServer" || continue

            read -p "Máscara de red (ej. 255.0.0.0): " mascara
            prefix=$(ipcalc -p "$ipServer" "$mascara" | cut -d= -f2)
            net_id=$(ipcalc -n "$ipServer" "$mascara" | cut -d= -f2)

            sudo nmcli device modify "enp0s8" ipv4.addresses "$ipServer/$prefix" ipv4.method manual
            sudo nmcli device up "enp0s8" &> /dev/null

            ipInicio=$ipServer
            echo -e "\e[33mEl rango iniciará en: $ipInicio\e[0m"
            read -p "IP Final del rango: " ipFinal

            sudo bash -c "cat > /etc/dhcp/dhcpd.conf <<EOF
authoritative;
ddns-update-style none;

# Usamos \$net_id para que siempre sea X.0.0.0 y no falle
subnet $net_id netmask $mascara {
    range $ipInicio $ipFinal;
    option routers $ipServer;
    option domain-name-servers 8.8.8.8;
    default-lease-time 3600;
    max-lease-time 7200;
}
EOF"

            sudo systemctl stop dhcpd &> /dev/null
            sudo sh -c "> /var/lib/dhcpd/dhcpd.leases"
            
            if sudo systemctl start dhcpd; then
                echo -e "\e[32m¡Servidor DHCP Activo en la red $net_id!\e[0m"
            else
                echo -e "\e[31mError de sintaxis. Revisa /etc/dhcp/dhcpd.conf\e[0m"
                sudo journalctl -u dhcpd -n 10 --no-pager
            fi
            read -p "Presione Enter..."
            ;;
        "4")
            echo -e "\e[33m\nLeases activos:\e[0m"
            [ -f /var/lib/dhcpd/dhcpd.leases ] && sudo grep -E "lease|hostname|ends" /var/lib/dhcpd/dhcpd.leases || echo "Vacio."
            read -p "Presione Enter..."
            ;;
        "5")
            echo -e "\e[31m\nLimpiando base de datos de leases...\e[0m"
            sudo systemctl stop dhcpd
            sudo sh -c "> /var/lib/dhcpd/dhcpd.leases"
            sudo systemctl start dhcpd
            echo -e "\e[32mLeases eliminados y servicio reiniciado.\e[0m"
            read -p "Presione Enter..."
            ;;
        "6")
            exit 0
            ;;
    esac
done

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
            
            while true; do
                read -p "IP Inicial: " ipServer
                validar_ip "$ipServer" && break
            done

            while true; do
                read -p "Introduce el prefijo de red: " prefix
                if [[ "$prefix" =~ ^[0-9]+$ ]] && [ "$prefix" -ge 8 ] && [ "$prefix" -le 30 ]; then
                    break
                else
                    echo -e "\e[31mError: El prefijo debe ser un número entre 8 y 30.\e[0m"
                fi
            done

            mascara=$(ipcalc -m "$ipServer/$prefix" | cut -d= -f2)
            net_id=$(ipcalc -n "$ipServer/$prefix" | cut -d= -f2)

            interface="enp0s8"            
            sudo nmcli device modify "$interface" ipv4.addresses "$ipServer/$prefix" ipv4.method manual
            sudo nmcli device up "$interface" &> /dev/null

            IFS='.' read -r a b c d <<< "$ipServer"
            ipInicio="$a.$b.$c.$((d + 1))"
            
            while true; do
                read -p "IP Final: " ipFinal
                if validar_ip "$ipFinal"; then
                    numInicio=$(ip_a_numero "$ipInicio")
                    numFinal=$(ip_a_numero "$ipFinal")
                    
                    if [ "$numFinal" -gt "$numInicio" ] && ipcalc -c "$ipFinal/$prefix" &> /dev/null; then
                        break
                    else
                        echo -e "\e[31mError: IP inválida o fuera de la red $net_id/$prefix\e[0m"
                    fi
                fi
            done

            read -p "Lease Time (sec): " leaseSec
            [[ -z "$leaseSec" ]] && leaseSec=3600
            read -p "Gateway [$ipServer]: " gw
            [[ -z "$gw" ]] && gw=$ipServer 
            read -p "DNS [8.8.8.8]: " dns
            [[ -z "$dns" ]] && dns="8.8.8.8"

sudo bash -c "cat > /etc/dhcp/dhcpd.conf <<EOF
authoritative;
ddns-update-style none;

# Usamos variables calculadas arriba
subnet $net_id netmask $mascara {
    range $ipInicio $ipFinal;
    option routers $gw;
    option domain-name-servers $dns;
    default-lease-time $leaseSec;
    max-lease-time $leaseSec;
}
EOF"

            sudo touch /var/lib/dhcpd/dhcpd.leases
            if sudo systemctl restart dhcpd; then
                echo -e "\e[32m¡Servidor DHCP Activo en $net_id/$prefix!\e[0m"
            else
                echo -e "\e[31mError al arrancar.\e[0m"
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

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

            mascara=$(ipcalc -m "$ipServer" | cut -d= -f2)
            net_id=$(ipcalc -n "$ipServer" | cut -d= -f2)
            prefix=$(ipcalc -p "$ipServer" | cut -d= -f2)

            interface="enp0s8"
            echo "Configurando $interface con IP $ipServer/$prefix..."
            sudo nmcli device modify "$interface" ipv4.addresses "$ipServer/$prefix" ipv4.method manual
            sudo nmcli device up "$interface" &> /dev/null

            IFS='.' read -r a b c d <<< "$ipServer"
            ipInicio="$a.$b.$c.$((d + 1))"
            
            while true; do
                read -p "IP Final: " ipFinal
                if validar_ip "$ipFinal"; then
                    [[ $(ip_a_numero "$ipFinal") -gt $(ip_a_numero "$ipInicio") ]] && break
                fi
                echo "IP inválida o fuera del rango de red."
            done

            read -p "Lease Time (sec): " leaseSec
            [[ -z "$leaseSec" ]] && leaseSec=3600
            read -p "Gateway [$ipServer]: " gw
            [[ -z "$gw" ]] && gw=$ipServer 
            read -p "DNS: " dns
            [[ -z "$dns" ]] && dns="8.8.8.8"

            sudo bash -c "cat > /etc/dhcp/dhcpd.conf <<EOF
authoritative;
ddns-update-style none;

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
                echo -e "\e[32mServidor DHCP Activo en Red $net_id con Máscara $mascara\e[0m"
            else
                echo -e "\e[31mFalló el arranque. Verifica que la red $net_id coincida con tu IP.\e[0m"
                sudo journalctl -u dhcpd -n 5 --no-pager
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

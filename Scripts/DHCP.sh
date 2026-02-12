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
                read -p "Máscara de red (ej. 255.0.0.0 o 255.255.255.0): " mascara
                if [[ $mascara =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                    prefix=$(ipcalc -p "$ipServer" "$mascara" | cut -d= -f2)
                    net_id=$(ipcalc -n "$ipServer" "$mascara" | cut -d= -f2)
                    
                    if [ -n "$prefix" ] && [ -n "$net_id" ]; then break; fi
                fi
                echo -e "\e[31mMáscara inválida. Intente de nuevo.\e[0m"
            done

            interface="enp0s8"
            echo "Configurando $interface con IP $ipServer/$prefix..."
            sudo nmcli device modify "$interface" ipv4.addresses "$ipServer/$prefix" ipv4.method manual
            sudo nmcli device up "$interface" &> /dev/null

            ipInicio=$ipServer
            
            while true; do
                echo -e "\e[33mEl rango iniciará en: $ipInicio\e[0m"
                read -p "IP Final del rango: " ipFinal
                if validar_ip "$ipFinal"; then
                    numInicio=$(ip_a_numero "$ipInicio")
                    numFinal=$(ip_a_numero "$ipFinal")
                    
                    if [ "$numFinal" -ge "$numInicio" ] && ipcalc -c "$ipFinal/$prefix" &> /dev/null; then
                        break
                    else
                        echo -e "\e[31mError: IP final inválida o fuera de la red $net_id\e[0m"
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

subnet $net_id netmask $mascara {
    range $ipInicio $ipFinal;
    option routers $gw;
    option domain-name-servers $dns;
    default-lease-time $leaseSec;
    max-lease-time $leaseSec;
}
EOF"

            # Limpieza de leases viejos y reinicio
            sudo sh -c "> /var/lib/dhcpd/dhcpd.leases"
            if sudo systemctl restart dhcpd; then
                echo -e "\e[32m¡Servidor DHCP Activo en red $net_id!\e[0m"
            else
                echo -e "\e[31mError al arrancar. Revisa la sintaxis en /etc/dhcp/dhcpd.conf\e[0m"
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

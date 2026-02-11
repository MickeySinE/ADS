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

    echo " ----- DHCP FEDORA SERVER ----- "
    echo "1) Verificar estado"
    echo "2) Instalar/Desinstalar"
    echo "3) Configurar"
    echo "4) Leases"
    echo "5) Salir"
    echo ""
    read -p "Seleccione una opcion: " opcion
    echo "$opcion"
    case $opcion in
    
        "1")
            status=$(systemctl is-active dhcpd)
            installed=$(rpm -q dhcp-server)
            if [[ $? -ne 0 ]]; then
                echo -e "\e[33m\nEstado del rol: No instalado\e[0m"
            else
                echo -e "\e[33m\nEstado del servicio: $status\e[0m"
            fi
            read -p "Presione Enter para continuar..."
            ;;

        "2")
            echo "Escriba 'I' para Instalar o 'D' para Desinstalar"
            read accion
            if [[ ${accion^^} == 'I' ]]; then
                sudo dnf install -y dhcp-server
            elif [[ ${accion^^} == 'D' ]]; then
                sudo dnf remove -y dhcp-server
            fi
            read -p "Presione Enter para continuar..."
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

            primerOcteto=$(echo $ipServer | cut -d. -f1)
            if [ $primerOcteto -le 126 ]; then
                mascara="255.0.0.0"; prefix=8; netmask_short="255.0.0.0"
            elif [ $primerOcteto -le 191 ]; then
                mascara="255.255.0.0"; prefix=16; netmask_short="255.255.0.0"
            else
                mascara="255.255.255.0"; prefix=24; netmask_short="255.255.255.0"
            fi

            interface=$(nmcli -t -f DEVICE,STATE device | grep ":connected" | cut -d: -f1 | head -n 1)
            if [ -n "$interface" ]; then
                sudo nmcli device modify "$interface" ipv4.addresses "$ipServer/$prefix" ipv4.method manual
                sudo nmcli device up "$interface"
                echo -e "\e[32mServidor configurado en $ipServer sobre $interface\e[0m"
            fi

            IFS='.' read -r a b c d <<< "$ipServer"
            ipInicio="$a.$b.$c.$((d + 1))"
            numInicio=$(ip_a_numero "$ipInicio")
            numServer=$(ip_a_numero "$ipServer")

            while true; do
                read -p "IP Final: " ipFinal
                if validar_ip "$ipFinal"; then
                    numFinal=$(ip_a_numero "$ipFinal")
                    if [ "$numFinal" -eq "$numServer" ]; then
                        echo -e "\e[31mError: La IP final no puede ser la IP del Servidor.\e[0m"
                    elif [ "$numFinal" -lt "$numInicio" ]; then
                        echo -e "\e[31mError: La IP final ($ipFinal) debe ser MAYOR a la inicial ($ipInicio).\e[0m"
                    else
                        break
                    fi
                fi
            done

            while true; do
                read -p "Lease Time (segundos): " leaseSec
                [[ "$leaseSec" =~ ^[0-9]+$ ]] && [ "$leaseSec" -gt 0 ] && break
                echo -e "\e[31mError: Ingrese un numero entero valido.\e[0m"
            done

            read -p "Gateway (Enter para saltar): " gw
            read -p "DNS (Enter para saltar): " dns

            net_id="$a.$b.$c.0"

            cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf > /dev/null
# Ambito: $nombreAmbito
subnet $net_id netmask $mascara {
  range $ipInicio $ipFinal;
  default-lease-time $leaseSec;
  max-lease-time $leaseSec;
EOF
            [[ -n "$gw" ]] && echo "  option routers $gw;" | sudo tee -a /etc/dhcp/dhcpd.conf
            [[ -n "$dns" ]] && echo "  option domain-name-servers $dns;" | sudo tee -a /etc/dhcp/dhcpd.conf
            echo "}" | sudo tee -a /etc/dhcp/dhcpd.conf

            sudo systemctl restart dhcpd && echo -e "\e[32mAmbito activado exitosamente.\e[0m" || echo -e "\e[31mError al iniciar el servicio.\e[0m"
            read -p "Presione Enter..."
            ;;

        "4")
            echo -e "\e[33m\nLeases activos:\e[0m"
            if [ -f /var/lib/dhcpd/dhcpd.leases ]; then
                grep -E "lease|hostname|ends" /var/lib/dhcpd/dhcpd.leases
            else
                echo "No hay base de datos de leases aún."
            fi
            read -p "Presione Enter..."
            ;;

        "5")
            exit 0
            ;;
    esac
done

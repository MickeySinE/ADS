#!/bin/bash

validar_ip() {
    local ip=$1
    if [[ $ip == "0.0.0.0" || $ip == "255.255.255.255" || $ip == "127.0.0.1" ]]; then
        return 1
    fi
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r r1 r2 r3 r4 <<< "$ip"
        for octeto in "$r1" "$r2" "$r3" "$r4"; do
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
    echo "3) Configurar Ambito (Nueva IP)"
    echo "4) Ver Leases (Clientes)"
    echo "5) Limpiar Base de Datos (Leases)"
    echo "6) Salir"
    echo ""
    read -p "Seleccione una opcion: " opcion

    case $opcion in
        "1")
            if systemctl is-active --quiet dhcpd; then
                echo -e "\e[32m\nEstado: ACTIVO\e[0m"
            else
                echo -e "\e[31m\nEstado: INACTIVO o ERROR\e[0m"
                echo "Log de error:"
                sudo journalctl -u dhcpd -n 5 --no-pager
            fi
            read -p "Presione Enter..."
            ;;

        "2")
            echo "Escriba 'I' para Instalar o 'D' para Desinstalar"
            read accion
            if [[ ${accion^^} == 'I' ]]; then
                sudo dnf install -y dhcp-server
                sudo firewall-cmd --add-service=dhcp --permanent
                sudo firewall-cmd --reload
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

            primerOcteto=$(echo $ipServer | cut -d. -f1)
            if [ $primerOcteto -le 126 ]; then
                mascara="255.0.0.0"; prefix=8; net_id="$(echo $ipServer | cut -d. -f1).0.0.0"
            elif [ $primerOcteto -le 191 ]; then
                mascara="255.255.0.0"; prefix=16; net_id="$(echo $ipServer | cut -d. -f1-2).0.0"
            else
                mascara="255.255.255.0"; prefix=24; net_id="$(echo $ipServer | cut -d. -f1-3).0"
            fi

            interface="enp0s8"
            echo "Configurando interfaz $interface..."
            sudo nmcli device modify "$interface" ipv4.addresses "$ipServer/$prefix" ipv4.method manual
            sudo nmcli device up "$interface" &> /dev/null

            IFS='.' read -r a b c d <<< "$ipServer"
            ipInicio="$a.$b.$c.$((d + 1))"
            numServer=$(ip_a_numero "$ipServer")

            while true; do
                echo -e "\e[33mRango sugerido empieza en: $ipInicio\e[0m"
                read -p "IP Final: " ipFinal
                if validar_ip "$ipFinal"; then
                    numFinal=$(ip_a_numero "$ipFinal")
                    if [ "$numFinal" -le "$numServer" ]; then
                        echo -e "\e[31mError: La IP final debe ser mayor a la del servidor.\e[0m"
                    else
                        break
                    fi
                fi
            done

            read -p "Lease Time (segundos): " leaseSec
            read -p "Gateway (Enter para usar la IP del server): " gw
            [[ -z "$gw" ]] && gw=$ipServer
            read -p "DNS (Enter para saltar): " dns
            [[ -z "$dns" ]] && dns="8.8.8.8"

            cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf > /dev/null
# Ambito: $nombreAmbito
subnet $net_id netmask $mascara {
  range $ipInicio $ipFinal;
  option routers $gw;
  option domain-name-servers $dns;
  default-lease-time $leaseSec;
  max-lease-time $leaseSec;
}
EOF
            # CONFIGURACIÓN EXTRA: Forzar escucha en enp0s8
            sudo sed -i 's/DHCPDARGS=.*/DHCPDARGS=enp0s8/' /etc/sysconfig/dhcpd 2>/dev/null || echo "DHCPDARGS=enp0s8" | sudo tee /etc/sysconfig/dhcpd

            sudo systemctl restart dhcpd && echo -e "\e[32m\n¡Ambito '$nombreAmbito' activado! IP: $ipServer\e[0m" || echo -e "\e[31mError al iniciar.\e[0m"
            read -p "Presione Enter..."
            ;;

        "4")
            echo -e "\e[33m\nLeases activos:\e[0m"
            if [ -f /var/lib/dhcpd/dhcpd.leases ]; then
                sudo grep -E "lease|hostname|ends" /var/lib/dhcpd/dhcpd.leases
            else
                echo "Sin base de datos de leases."
            fi
            read -p "Presione Enter..."
            ;;

        "5")
            echo "Limpiando base de datos de leases..."
            sudo systemctl stop dhcpd
            sudo truncate -s 0 /var/lib/dhcpd/dhcpd.leases
            sudo systemctl start dhcpd
            echo "¡Listo! Base de datos reiniciada."
            read -p "Presione Enter..."
            ;;

        "6")
            exit 0
            ;;
    esac
done

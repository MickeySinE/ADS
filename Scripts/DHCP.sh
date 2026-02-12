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
    echo "5) Eliminar leases"
    echo "6) Salir"
    echo ""
    read -p "Seleccione una opcion: " opcion
    echo "$opcion"
    case $opcion in
    
        "1")
            if systemctl is-active --quiet dhcpd; then
                echo -e "\e[32m\nEstado del servicio: ACTIVO (Corriendo)\e[0m"
            else
                echo -e "\e[31m\nEstado del servicio: INACTIVO o ERROR\e[0m"
                echo "Último error: "
                sudo journalctl -u dhcpd -n 1 --no-pager
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
        read -p "IP del Servidor (se usará como base): " ipServer
        validar_ip "$ipServer" && break
    done

    primerOcteto=$(echo $ipServer | cut -d. -f1)
    if [ $primerOcteto -le 126 ]; then
        mascara="255.0.0.0"; prefix=8
    elif [ $primerOcteto -le 191 ]; then
        mascara="255.255.0.0"; prefix=16
    else
        mascara="255.255.255.0"; prefix=24
    fi

    interface="enp0s8"
    echo "Configurando interfaz $interface..."
    sudo nmcli device modify "$interface" ipv4.addresses "$ipServer/$prefix" ipv4.method manual
    sudo nmcli device up "$interface" &> /dev/null
    echo -e "\e[32mInterfaz $interface actualizada a $ipServer\e[0m"

    IFS='.' read -r a b c d <<< "$ipServer"
    
    ipInicio="$a.$b.$c.$((d + 1))"
    numInicio=$(ip_a_numero "$ipInicio")
    numServer=$(ip_a_numero "$ipServer")
    
    if [ $prefix -eq 8 ]; then net_id="$a.0.0.0"
    elif [ $prefix -eq 16 ]; then net_id="$a.$b.0.0"
    else net_id="$a.$b.$c.0"; fi

    while true; do
        echo -e "\e[33mSugerencia: El rango de clientes empieza en $ipInicio\e[0m"
        read -p "IP Final: " ipFinal
        if validar_ip "$ipFinal"; then
            numFinal=$(ip_a_numero "$ipFinal")
            if [ "$numFinal" -eq "$numServer" ]; then
                echo -e "\e[31mError: La IP final no puede ser la IP del Servidor.\e[0m"
            elif [ "$numFinal" -lt "$numInicio" ]; then
                echo -e "\e[31mError: La IP final debe ser MAYOR a $ipInicio.\e[0m"
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

    read -p "Gateway (Enter para saltar: " gw
    [[ -z "$gw" ]] && gw=$ipServer # 
    read -p "DNS (Enter para saltar): " dns

    cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf > /dev/null
# Ambito: $nombreAmbito
subnet $net_id netmask $mascara {
  range $ipInicio $ipFinal;
  default-lease-time $leaseSec;
  max-lease-time $leaseSec;
EOF
    [[ -n "$gw" ]] && echo "  option routers $gw;" | sudo tee -a /etc/dhcp/dhcpd.conf
    [[ -n "$dns" ]] && echo "  option domain-name-servers $dns;" | sudo tee -a /etc/dhcp/dhcpd.conf
    echo "}" | sudo tee -a /etc/dhcp/dhcpd.conf

    # --- REINICIO Y VERIFICACIÓN ---
    sudo systemctl restart dhcpd && echo -e "\e[32mAmbito '$nombreAmbito' activado exitosamente.\e[0m" || echo -e "\e[31mError al iniciar el servicio.\e[0m"
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
            echo -e "\e[31m\n--- Eliminando Leases Activos ---\e[0m"
            read -p "¿Está seguro de que desea eliminar todas las sesiones? (s/n): " confirmar
            if [[ ${confirmar^^} == 'S' ]]; then
                sudo systemctl stop dhcpd
                
                if [ -f /var/lib/dhcpd/dhcpd.leases ]; then
                    sudo truncate -s 0 /var/lib/dhcpd/dhcpd.leases
                    echo -e "\e[32mArchivo de leases vaciado.\e[0m"
                else
                    echo "No se encontró el archivo de leases, nada que limpiar."
                fi
                
                sudo systemctl start dhcpd
                echo -e "\e[32mServicio reiniciado y tabla de leases limpia.\e[0m"
            else
                echo "Operación cancelada."
            fi
            read -p "Presione Enter para continuar..."
            ;;
        "6")
            exit 0
            ;;
    esac

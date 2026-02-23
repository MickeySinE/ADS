#!/bin/bash

INTERFAZ="enp0s8"

validar_ip() {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

verificar_ip_fija() {
    is_manual=$(nmcli -g ipv4.method device show "$INTERFAZ" 2>/dev/null)
    if [[ "$is_manual" != "manual" ]]; then
        echo -e "\e[33m[!] Red en modo DHCP.\e[0m"
        read -p "¿Configurar IP fija ahora? (s/n): " conf
        if [[ ${conf^^} == 'S' ]]; then
            read -p "IP del servidor: " ip_s
            read -p "Máscara (ej. 24): " mask_s
            read -p "Gateway: " gw_s
            sudo nmcli con mod "$INTERFAZ" ipv4.addresses "$ip_s/$mask_s" ipv4.gateway "$gw_s" ipv4.method manual
            sudo nmcli con up "$INTERFAZ"
            echo -e "\e[32mIP fija establecida.\e[0m"
        fi
    fi
}

verificar_estado() {
    if rpm -q bind &> /dev/null; then
        echo -e "\e[32mBIND9 instalado.\e[0m"
        echo -n "Estado: "
        systemctl is-active named --quiet && echo -e "\e[32mACTIVO\e[0m" || echo -e "\e[31mINACTIVO\e[0m"
    else
        echo -e "\e[31mBIND9 NO instalado.\e[0m"
    fi
}

instalar_servicio() {
    if rpm -q bind &> /dev/null; then
        echo "El servicio ya existe."
    else
        sudo dnf install -y bind bind-utils
        sudo systemctl enable named --now
        sudo firewall-cmd --add-service=dns --permanent &> /dev/null
        sudo firewall-cmd --reload &> /dev/null
        echo -e "\e[32mInstalado correctamente.\e[0m"
    fi
}

listar_dominios() {
    echo -e "\e[34mZonas actuales:\e[0m"
    sudo grep "zone" /etc/named.conf | awk -F'"' '{print $2}' | grep -v "^\."
}

agregar_dominio() {
    read -p "Nombre del dominio a crear: " dominio
    if [[ -z "$dominio" ]]; then echo "Error: Dominio vacío"; return; fi
    
    read -p "IP destino (Cliente): " ip_dest
    validar_ip "$ip_dest" || { echo "IP inválida"; return; }

    if ! sudo grep -q "zone \"$dominio\"" /etc/named.conf; then
        sudo bash -c "cat >> /etc/named.conf <<EOF
zone \"$dominio\" IN {
    type master;
    file \"db.$dominio\";
    allow-update { none; };
};
EOF"
    fi

sudo bash -c "cat > /var/named/db.$dominio <<EOF
\$TTL 86400
@ IN SOA ns1.$dominio. admin.$dominio. (
    $(date +%Y%m%d)01 ; Serial
    3600             ; Refresh
    1800             ; Retry
    604800           ; Expire
    86400 )          ; Minimum
@ IN NS ns1.$dominio.
ns1 IN A $ip_dest
@ IN A $ip_dest
www IN A $ip_dest
EOF"

    sudo chown named:named "/var/named/db.$dominio"
    sudo chmod 640 "/var/named/db.$dominio"
    
    if sudo named-checkconf /etc/named.conf && sudo named-checkzone "$dominio" "/var/named/db.$dominio"; then
        sudo systemctl restart named
        echo -e "\e[32mDominio $dominio configurado.\e[0m"
    else
        echo -e "\e[31mError en archivos de configuración.\e[0m"
    fi
}

eliminar_dominio() {
    listar_dominios
    read -p "Dominio a eliminar: " dominio
    if [[ -z "$dominio" ]]; then return; fi

    sudo sed -i "/zone \"$dominio\"/,/};/d" /etc/named.conf
    sudo rm -f "/var/named/db.$dominio"
    sudo systemctl restart named
    echo -e "\e[31mDominio $dominio borrado.\e[0m"
}

clear
verificar_ip_fija

while true; do
    echo -e "\n========= MENÚ DNS ========="
    echo "1) Estado del servicio"
    echo "2) Instalar BIND9"
    echo "3) Listar dominios"
    echo "4) Agregar nuevo dominio"
    echo "5) Eliminar dominio"
    echo "6) Salir"
    echo "============================"
    read -p "Opción: " opcion

    case $opcion in
        1) verificar_estado ;;
        2) instalar_servicio ;;
        3) listar_dominios ;;
        4) agregar_dominio ;;
        5) eliminar_dominio ;;
        6) exit 0 ;;
        *) echo "No válida" ;;
    esac
    read -p "Enter para continuar..."
done

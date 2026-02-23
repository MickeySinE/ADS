#!/bin/bash

validar_ip() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
}

verificar_ip_fija() {
    interface="enp0s8"
    is_dhcp=$(nmcli -g ipv4.method device show "$interface" 2>/dev/null)

    if [[ "$is_dhcp" == "auto" ]] || [[ -z "$is_dhcp" ]]; then
        echo -e "\e[33mAdvertencia: No se detectó una IP fija en $interface.\e[0m"
        read -p "¿Desea configurar IP fija ahora? (s/n): " conf
        if [[ ${conf^^} == 'S' ]]; then
            read -p "IP deseada: " ip_f
            read -p "Mascara: " mask_f
            read -p "Gateway: " gw_f
            prefix=$(ipcalc -p "$ip_f" "$mask_f" | cut -d= -f2)
            
            sudo nmcli device modify "$interface" ipv4.addresses "$ip_f/$prefix" ipv4.gateway "$gw_f" ipv4.method manual
            sudo nmcli device up "$interface"
            echo -e "\e[32mIP fija configurada.\e[0m"
        fi
    else
        echo -e "\e[32mConfirmado: La interfaz $interface tiene IP manual.\e[0m"
    fi
}

verificar_instalacion() {
    if rpm -q bind &> /dev/null; then
        echo -e "\e[32mBIND9 está instalado.\e[0m"
        systemctl is-active --quiet named && echo "Estado: ACTIVO" || echo "Estado: INACTIVO"
    else
        echo -e "\e[31mBIND9 NO está instalado.\e[0m"
    fi
}

instalar_dependencias() {
    sudo dnf install -y bind bind-utils
    sudo systemctl enable named --now
    sudo firewall-cmd --add-service=dns --permanent &> /dev/null
    sudo firewall-cmd --reload &> /dev/null
    echo -e "\e[32mInstalación completada.\e[0m"
}

listar_dominios() {
    echo -e "\e[34mZonas configuradas en named.conf:\e[0m"
    sudo grep "zone" /etc/named.conf | awk -F'"' '{print $2}' | grep -v "^\."
}

agregar_dominio() {
    read -p "Nombre del dominio: " dominio
    read -p "IP: " ip_dest
    validar_ip "$ip_dest" || { echo "IP inválida"; return; }

    if ! sudo grep -q "zone \"$dominio\"" /etc/named.conf; then
        sudo bash -c "cat >> /etc/named.conf <<EOF
zone \"$dominio\" IN {
    type master;
    file \"db.$dominio\";
};
EOF"
    fi

    sudo bash -c "cat > /var/named/db.$dominio <<EOF
\$TTL 86400
@ IN SOA ns1.$dominio. admin.$dominio. (
    $(date +%Y%m%d)01
    3600
    1800
    604800
    86400 )
;
@ IN NS ns1.$dominio.
ns1 IN A $ip_dest
@ IN A $ip_dest
www IN A $ip_dest
EOF"

    sudo chown named:named "/var/named/db.$dominio"
    sudo chmod 640 "/var/named/db.$dominio"
    
    if sudo named-checkconf /etc/named.conf && sudo named-checkzone $dominio /var/named/db.$dominio; then
        sudo systemctl restart named
        echo -e "\e[32mDominio $dominio agregado exitosamente.\e[0m"
    else
        echo -e "\e[31mError en la configuración.\e[0m"
    fi
}

eliminar_dominio() {
    read -p "Dominio a eliminar: " dominio
    sudo sed -i "/zone \"$dominio\"/,/};/d" /etc/named.conf
    sudo rm -f "/var/named/db.$dominio"
    sudo systemctl restart named
    echo -e "\e[31mDominio $dominio eliminado.\e[0m"
}

clear
verificar_ip_fija

while true; do
    echo ""
    echo "========= MENÚ DNS ========="
    echo "1) Verificar instalación"
    echo "2) Instalar dependencias"
    echo "3) Listar Dominios configurados"
    echo "4) Agregar nuevo dominio"
    echo "5) Eliminar un dominio"
    echo "6) Salir"
    echo "============================="
    read -p "Seleccione una opcion: " opcion

    case $opcion in
        1) verificar_instalacion ;;
        2) instalar_dependencias ;;
        3) listar_dominios ;;
        4) agregar_dominio ;;
        5) eliminar_dominio ;;
        6) exit 0 ;;
        *) echo "Opción no válida" ;;
    esac
    read -p "Presione Enter para continuar..."
done

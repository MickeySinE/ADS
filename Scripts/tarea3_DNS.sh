#!/bin/bash

verificar_ip_fija() {
    IP_ACTUAL=$(hostname -I | awk '{print $1}')
    if [[ $IP_ACTUAL =~ ^169\.254 || -z $IP_ACTUAL ]]; then
        read -p "IP fija deseada: " NUEVA_IP
        read -p "Máscara (ej. 24): " MASCARA
        read -p "Gateway: " PUERTA
        echo "Configurando $NUEVA_IP..."
    fi
}

instalar_servicio() {
    if ! dpkg -l | grep -q bind9; then
        sudo apt update && sudo apt install -y bind9 bind9utils bind9-doc
    fi
}

gestionar_dominio() {
    DOMINIO="reprobados.com"
    ARCHIVO_ZONA="/var/cache/bind/db.$DOMINIO"
    IP_DESTINO=$1

    if ! grep -q "$DOMINIO" /etc/bind/named.conf.local; then
        cat <<EOF | sudo tee -a /etc/bind/named.conf.local
zone "$DOMINIO" {
    type master;
    file "$ARCHIVO_ZONA";
};
EOF
    fi

    cat <<EOF | sudo tee $ARCHIVO_ZONA
\$TTL 604800
@   IN  SOA ns1.$DOMINIO. admin.$DOMINIO. (
                  3     ; Serial
             604800     ; Refresh
              86400     ; Retry
            2419200     ; Expire
             604800 )   ; Negative Cache
;
@   IN  NS  ns1.$DOMINIO.
@   IN  A   $IP_DESTINO
ns1 IN  A   $IP_DESTINO
www IN  A   $IP_DESTINO
EOF

    sudo named-checkconf
    sudo systemctl restart bind9
}

while true; do
    clear
    echo "1. Instalar y Validar IP"
    echo "2. Alta/Actualizar Dominio"
    echo "3. Baja de Dominio"
    echo "4. Salir"
    read -p "Opción: " OP

    case $OP in
        1) verificar_ip_fija; instalar_servicio ;;
        2) read -p "IP Destino: " IP_VMC; gestionar_dominio $IP_VMC ;;
        3) sudo sed -i "/zone \"reprobados.com\"/,/};/d" /etc/bind/named.conf.local
           sudo rm -f /var/cache/bind/db.reprobados.com
           sudo systemctl restart bind9 ;;
        4) break ;;
    esac
done

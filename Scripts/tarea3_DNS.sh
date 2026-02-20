#!/bin/bash

verificar_instalacion() {
    if dpkg -l | grep -q bind9; then
        echo "Servicio instalado y $(systemctl is-active bind9)"
    else
        echo "BIND9 no está instalado."
    fi
}

instalar_dependencias() {
    IP_ACTUAL=$(hostname -I | awk '{print $1}')
    if [[ $IP_ACTUAL =~ ^169\.254 || -z $IP_ACTUAL ]]; then
        echo "No se detecta IP fija."
        read -p "Ingrese IP estática: " NUEVA_IP
        read -p "Prefijo (ej. 24): " MASK
        read -p "Gateway: " GW
        echo "Configure la IP en su interfaz antes de continuar."
    fi
    sudo apt update && sudo apt install -y bind9 bind9utils bind9-doc
}

listar_dominios() {
    grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2
}

agregar_dominio() {
    read -p "Nombre del dominio (ej: reprobados.com): " DOMINIO
    read -p "IP a la que apunta: " IP_DESTINO
    ARCHIVO_ZONA="/var/cache/bind/db.$DOMINIO"

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
    echo "Dominio $DOMINIO agregado."
}

eliminar_dominio() {
    read -p "Dominio a eliminar: " DOMINIO
    sudo sed -i "/zone \"$DOMINIO\"/,/};/d" /etc/bind/named.conf.local
    sudo rm -f /var/cache/bind/db.$DOMINIO
    sudo systemctl restart bind9
    echo "Dominio eliminado."
}

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
    read -p "Seleccione una opción: " OP

    case $OP in
        1) verificar_instalacion ;;
        2) instalar_dependencias ;;
        3) listar_dominios ;;
        4) agregar_dominio ;;
        5) eliminar_dominio ;;
        6) exit ;;
        *) echo "Opción inválida" ;;
    esac
done

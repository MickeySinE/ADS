#!/bin/bash

verificar_privilegios() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "[X] Error: Ejecuta como superusuario (sudo)."
        exit 1
    fi
}

obtener_entero() {
    local pregunta="$1"
    while true; do
        read -p "$pregunta: " valor
        if [[ "$valor" =~ ^[0-9]+$ ]] && [ "$valor" -gt 0 ]; then
            echo "$valor"
            return
        else
            echo "[!] Ingresa un número entero positivo."
        fi
    done
}

es_ip_valida() {
    local direccion_ip="$1"
    local estado=1
    if [[ "$direccion_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        partes_ip=($direccion_ip)
        IFS=$OIFS
        [[ ${partes_ip[0]} -le 255 && ${partes_ip[1]} -le 255 && \
           ${partes_ip[2]} -le 255 && ${partes_ip[3]} -le 255 ]]
        estado=$?
        if [ $estado -eq 0 ]; then
            if [[ "$direccion_ip" == "0.0.0.0" || "$direccion_ip" == "127.0.0.1" || "$direccion_ip" == "255.255.255.255" ]]; then
                return 1
            fi
        fi
    fi
    return $estado
}

leer_ip() {
    local pregunta="$1"
    local permite_vacio="${2:-no}"
    while true; do
        read -p "$pregunta: " ip_usuario
        if [[ "$permite_vacio" == "si" && -z "$ip_usuario" ]]; then
            echo ""
            return
        fi
        if es_ip_valida "$ip_usuario"; then
            echo "$ip_usuario"
            return
        else
            echo "[X] IP no válida."
        fi
    done
}

instalar_dhcp() {
    echo "[i] Comprobando DHCP..."
    if ! rpm -q dhcp-server &>/dev/null; then
        dnf install -y dhcp-server
    fi
    systemctl enable dhcpd
    echo "[V] DHCP listo para configurar."
    read -p "Presiona Enter para continuar..."
}

configurar_rango_dhcp() {
    if ! rpm -q dhcp-server &>/dev/null; then
        echo "[X] Error: Primero instala el servicio DHCP."
        return
    fi

    nmcli device status
    read -p "Interfaz de red [ens33]: " interfaz
    [ -z "$interfaz" ] && interfaz="ens33"

    ip_servidor=$(nmcli -g IP4.ADDRESS device show "$interfaz" 2>/dev/null | cut -d'/' -f1)
    if [ -z "$ip_servidor" ]; then
        ip_servidor=$(leer_ip "IP Estática del Servidor")
    fi

    ip_inicio=$(leer_ip "IP Inicio del Rango")
    while true; do
        ip_fin=$(leer_ip "IP Fin del Rango")
        if [[ "$(echo "$ip_fin" | cut -d. -f4)" -gt "$(echo "$ip_inicio" | cut -d. -f4)" ]]; then
            break
        else
            echo "[!] El final del rango debe ser mayor al inicio."
        fi
    done

    read -p "Prefijo de red (24/16/8) [24]: " cidr
    [ -z "$cidr" ] && cidr=24
    case $cidr in
        16) mascara="255.255.0.0" ;;
        8)  mascara="255.0.0.0" ;;
        *)  mascara="255.255.255.0"; cidr=24 ;;
    esac

    ip_gw=$(leer_ip "Puerta de enlace (Enter para omitir)" "si")
    ip_dns=$(leer_ip "Servidor DNS")
    tiempo_concesion=$(obtener_entero "Tiempo de renta (segundos)")

    red_base=$(echo "$ip_inicio" | cut -d. -f1-3).0

    nmcli con mod "$interfaz" ipv4.addresses "${ip_servidor}/${cidr}" ipv4.method manual
    [ -n "$ip_gw" ] && nmcli con mod "$interfaz" ipv4.gateway "$ip_gw"
    nmcli con mod "$interfaz" ipv4.dns "$ip_dns"
    nmcli con up "$interfaz"

    printf "default-lease-time %s;\nmax-lease-time %s;\n\nsubnet %s netmask %s {\n  range %s %s;\n  option domain-name-servers %s;\n  option subnet-mask %s;\n%s}\n" \
    "$tiempo_concesion" "$((tiempo_concesion * 2))" "$red_base" "$mascara" "$ip_inicio" "$ip_fin" "$ip_dns" "$mascara" \
    "$([ -n "$ip_gw" ] && echo "  option routers $ip_gw;")" > /etc/dhcp/dhcpd.conf

    echo "DHCPDARGS=$interfaz" > /etc/sysconfig/dhcpd
    systemctl restart dhcpd
    firewall-cmd --add-service=dhcp --permanent &>/dev/null
    firewall-cmd --reload &>/dev/null
    echo "[V] Rango DHCP configurado y activo."
    read -p "Presiona Enter para continuar..."
}

instalar_dns() {
    echo "[i] Instalando BIND9..."
    if ! rpm -q bind &>/dev/null; then
        dnf install -y bind bind-utils
    fi
    systemctl enable --now named
    echo "[V] Servicio DNS iniciado."
    read -p "Presiona Enter para continuar..."
}

ZONAS_LOCALES="/etc/named/custom.zones"

inicializar_config_zonas() {
    mkdir -p /etc/named
    [ ! -f "$ZONAS_LOCALES" ] && touch "$ZONAS_LOCALES" && chown named:named "$ZONAS_LOCALES"
    if ! grep -q "custom.zones" /etc/named.conf 2>/dev/null; then
        echo "include \"$ZONAS_LOCALES\";" >> /etc/named.conf
    fi
}

nuevo_dominio_dns() {
    inicializar_config_zonas

    read -p "Nombre del dominio a crear: " dominio
    read -p "IP destino: " ip_dest
    
    mapfile -t ips_disponibles < <(hostname -I | tr ' ' '\n' | grep -vE "127.0.0.1|10.0.2.15|^$")

    if [ ${#ips_disponibles[@]} -eq 0 ]; then
        echo "[!] No se detectaron IPs válidas automáticamente."
        ip_srv=$(leer_ip "Ingresa manualmente la IP de este servidor")
    elif [ ${#ips_disponibles[@]} -eq 1 ]; then
        ip_srv="${ips_disponibles[0]}"
        echo "[i] Usando IP detectada para el servidor: $ip_srv"
    else
        echo "Se detectaron varias IPs. ¿Cuál quieres que use el servidor DNS?"
        select opt in "${ips_disponibles[@]}"; do
            if [ -n "$opt" ]; then
                ip_srv=$opt
                break
            fi
        done
    fi

    if grep -q "\"$dominio\"" "$ZONAS_LOCALES"; then
        echo "[!] El dominio ya existe en $ZONAS_LOCALES"
        return
    fi

    sudo sed -i '/^};/d' "$ZONAS_LOCALES"

    sudo bash -c "cat >> $ZONAS_LOCALES <<EOF

zone \"$dominio\" IN {
    type master;
    file \"/var/named/db.$dominio\";
    allow-update { none; };
};
EOF"

    sudo bash -c "cat > /var/named/db.$dominio <<'EOF'
\$TTL 86400
@   IN  SOA ns1.$dominio. admin.$dominio. (
            $(date +%Y%m%d)01 ; Serial
            3600 ; Refresh
            1800 ; Retry
            604800 ; Expire
            86400 ) ; Minimum
@   IN  NS  ns1.$dominio.
ns1 IN  A   $ip_srv
@   IN  A   $ip_dest
www IN  A   $ip_dest
EOF"

    sudo chown named:named /var/named/db.$dominio
    sudo chmod 640 /var/named/db.$dominio
    
    sudo systemctl restart named
    if [ $? -eq 0 ]; then
        echo "[V] Dominio $dominio creado exitosamente con IP Servidor: $ip_srv"
    else
        echo "[X] Error al reiniciar BIND. Revisa la sintaxis."
    fi
    read -p "Enter para continuar..."
}

quitar_dominio_dns() {
    inicializar_config_zonas
    lista_dominios=($(grep "^zone" "$ZONAS_LOCALES" | awk '{print $2}' | tr -d '"'))
    [ ${#lista_dominios[@]} -eq 0 ] && echo "[i] No hay dominios." && read -p "Enter..." && return

    echo "Dominios actuales: ${lista_dominios[*]}"
    read -p "Dominio a eliminar: " borrar_target
    if grep -q "\"$borrar_target\"" "$ZONAS_LOCALES"; then
        python3 -c "import re; f=open('$ZONAS_LOCALES','r'); c=f.read(); f.close(); p=r'\n*zone \"$borrar_target\" IN \{[^}]*\};'; c=re.sub(p,'',c,flags=re.DOTALL); f=open('$ZONAS_LOCALES','w'); f.write(c); f.close()"
        rm -f /var/named/db.${borrar_target}
        systemctl restart named
        echo "[V] Dominio eliminado."
    fi
    read -p "Presiona Enter para continuar..."
}

mostrar_estado_servicios() {
    clear
    echo "=== ESTADO DE SERVICIOS ==="
    for srv in dhcpd named; do
        systemctl is-active "$srv" &>/dev/null && echo "$srv: ACTIVO" || echo "$srv: INACTIVO"
    done
    read -p "Presiona Enter para continuar..."
}

menu_dhcp() {
    while true; do
        clear
        echo "=== MENÚ DHCP ==="
        echo "1. Instalar Servidor"
        echo "2. Configurar Ámbito (Scope)"
        echo "3. Ver Concesiones (Leases)"
        echo "4. Desinstalar DHCP"
        echo "5. Volver al inicio"
        read -p ">> " opcion_dhcp
        case $opcion_dhcp in
            1) instalar_dhcp ;;
            2) configurar_rango_dhcp ;;
            3) [ -f /var/lib/dhcpd/dhcpd.leases ] && grep -E "lease|hostname" /var/lib/dhcpd/dhcpd.leases || echo "No hay clientes registrados."; read -p "Enter..." ;;
            4) dnf remove -y dhcp-server ;;
            5) break ;;
        esac
    done
}

menu_dns() {
    while true; do
        clear
        echo "=== MENÚ DNS ==="
        echo "1. Instalar BIND9"
        echo "2. Registrar Dominio"
        echo "3. Listar Registros"
        echo "4. Eliminar Dominio"
        echo "5. Desinstalar DNS"
        echo "6. Volver al inicio"
        read -p ">> " opcion_dns
        case $opcion_dns in
            1) instalar_dns ;;
            2) nuevo_dominio_dns ;;
            3) grep "^zone" "$ZONAS_LOCALES" | tr -d '"'; read -p "Enter..." ;;
            4) quitar_dominio_dns ;;
            5) dnf remove -y bind bind-utils ;;
            6) break ;;
        esac
    done
}

verificar_privilegios
while true; do
    clear
    echo "=== PANEL DE CONTROL (ADMIN) ==="
    echo "1. Gestión DHCP"
    echo "2. Gestión DNS"
    echo "3. Estado del Sistema"
    echo "4. Salir"
    read -p "Selección: " seleccion
    case $seleccion in
        1) menu_dhcp ;;
        2) menu_dns ;;
        3) mostrar_estado_servicios ;;
        4) exit 0 ;;
    esac
done

validar_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        if [[ $ip != "0.0.0.0" && $ip != "255.255.255.255" ]]; then
            return 0 
        fi
    fi
    return 1 
}

while true; do
    clear
    echo "==============================="
    echo "       MENU DHCP FEDORA        "
    echo "==============================="
    echo "1) Instalar/Verificar"
    echo "2) Configurar Ambito"
    echo "3) Monitorear"
    echo "4) Salir"
    read -p "Seleccione: " opt

    case $opt in
        1)
            echo "Verificando servicio DHCP..."
            if ! rpm -q dhcp-server &> /dev/null; then
                echo "Instalando servidor DHCP..."
                sudo dnf install -y dhcp-server
            else
                echo "El servidor DHCP ya esta instalado."
            fi
            read -p "Presiona Enter para continuar..."
            ;;
        2)
            read -p "Nombre del Ambito: " NAME
            while true; do
                read -p "IP Inicial: " START
                validar_ip "$START" && break
                echo "IP no valida, intenta de nuevo."
            done
            while true; do
                read -p "IP Final: " END
                validar_ip "$END" && break
                echo "IP no valida, intenta de nuevo."
            done
            read -p "Gateway (Router): " GW
            read -p "DNS Server (IP): " DNS

            NETWORK=$(echo $START | cut -d. -f1-3).0

            echo "Generando archivo de configuracion..."
            sudo bash -c "cat > /etc/dhcp/dhcpd.conf << EOF
# Ambito: $NAME
subnet $NETWORK netmask 255.255.255.0 {
  range $START $END;
  option routers $GW;
  option domain-name-servers $DNS;
  default-lease-time 600;
  max-lease-time 7200;
}
EOF"
            echo "Reiniciando el servicio..."
            sudo systemctl restart dhcpd
            sudo systemctl enable dhcpd
            echo "¡Ambito configurado y servicio activo!"
            read -p "Presiona Enter para continuar..."
            ;;
        3)
            echo "--- Estado del Servicio ---"
            systemctl status dhcpd | grep -E "Active|Status"
            echo -e "\n--- Clientes Conectados (Leases) ---"
            cat /var/lib/dhcpd/dhcpd.leases | grep -E "lease|hostname"
            read -p "Presiona Enter para continuar..."
            ;;
        4) 
            echo "Saliendo..."
            exit 0 
            ;;
        *)
            echo "Opcion no valida"
            sleep 1
            ;;
    esac
done

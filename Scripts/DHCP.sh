ip_to_int() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    echo "$(( (a << 24) + (b << 16) + (c << 8) + d ))"
}

validar_ip() {
    local ip=$1
    local stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        if [[ $ip != "0.0.0.0" && $ip != "255.255.255.255" ]]; then
            stat=0
        fi
    fi
    return $stat
}

while true; do
    echo -e "\n ----- DHCP FEDORA "
    echo "[1] Verificar/Instalar DHCP"
    echo "[2] Configurar Nuevo Ambito (Scope)"
    echo "[3] Monitorear Estado y Leases"
    echo "[4] Salir"
    read -p "Seleccione una opción: " opt

    case $opt in
        1)
            if ! rpm -q dhcp-server &>/dev/null; then
                sudo dnf install -y dhcp-server
            else echo "Ya instalado."; fi
            ;;
        2)
            read -p "Nombre Ámbito: " NAME
            while true; do
                read -p "IP Inicial: " START
                validar_ip $START && break
            done
            while true; do
                read -p "IP Final: " END
                if validar_ip $END && [ $(ip_to_int $END) -gt $(ip_to_int $START) ]; then break; fi
                echo "IP inválida o menor a la inicial."
            done
            
            cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
subnet 192.168.100.0 netmask 255.255.255.0 {
  range $START $END;
  option routers 192.168.100.1;
  option domain-name-servers 8.8.8.8;
  default-lease-time 600;
  max-lease-time 7200;
}
EOF
            sudo systemctl restart dhcpd && echo "Servidor Reiniciado."
            ;;
        3)
            sudo systemctl status dhcpd | grep Active
            echo "--- Concesiones detectadas ---"
            grep "lease" /var/lib/dhcpd/dhcpd.leases | sort | uniq
            ;;
        4) exit 0 ;;
    esac
done

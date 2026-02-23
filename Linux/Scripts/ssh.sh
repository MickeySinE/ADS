#!/bin/bash
instalar_ssh() {
    install_required_package "ipcalc"

    if ! check_package_present "openssh-server"; then
        echo "Instalando openssh-server..."
        install_required_package "openssh-server"
        if [[ $? -eq 0 ]]; then
            echo "Instalado con éxito"
        else 
            echo "Error al instalar"
            exit 1
        fi
    else 
        echo "Ya está instalado"
    fi
    
    configurar_ssh
}

configurar_ssh() {
    if ! systemctl is-enabled --quiet sshd; then
        systemctl enable sshd 
    fi

    if ! firewall-cmd -q --query-service ssh; then
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --reload
    fi

    if ! systemctl is-active --quiet sshd; then
        echo "El servicio estaba dormido, despertando..."
        systemctl start sshd
    fi
}

verificar() {
    if check_package_present "openssh-server"; then
        echo "[OK] SSH instalado"
    else
        echo "[X] SSH no instalado"
    fi
    configurar_ssh
}

conectar() {
    read -p "IP del servidor: " server
    read -p "Usuario: " user
    
    if [[ -z "$user" ]]; then
        echo "Usuario vacío, no se puede conectar"
    else
        ssh "$user@$server"
    fi
}

menu() {
    while true; do
        echo ""
        echo "--- MENU SSH FEDORA ---"
        echo "1) Verificar"
        echo "2) Instalar"
        echo "3) Conectarse"
        echo "4) Salir"
        read -p "Opcion: " op

        case $op in
            1) verificar ;;
            2) instalar_ssh ;;
            3) conectar ;;
            4) exit 0 ;;
            *) echo "No valido" ;;
        esac
    done
}

case "$1" in
    --check) verificar ;;
    --install) instalar_ssh ;;
    --connect) conectar ;;
    "") menu ;;
    *) echo "Uso: $0 [--check|--install|--connect]" ;;
esac

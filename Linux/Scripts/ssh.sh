#!/bin/bash

instalar_servidor() {
    echo "--- INSTALANDO SSH EN FEDORA ---"
    sudo dnf install -y openssh-server
    
    sudo systemctl enable sshd
    sudo systemctl start sshd
    
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --reload
    
    echo "[OK] Instalado, habilitado en boot y puerto 22 abierto."
}

conectar_remoto() {
    read -p "IP del servidor remoto: " ip
    read -p "Usuario: " user
    ssh "$user@$ip"
}

while true; do
    echo -e "\n--- SSH MANAGER ---"
    echo "1) Instalar y Activar Servidor SSH (Hito Crítico)"
    echo "2) Conectarse a otro servidor"
    echo "3) Salir"
    read -p "Selecciona una opción: " op

    case $op in
        1) instalar_servidor ;;
        2) conectar_remoto ;;
        3) exit 0 ;;
        *) echo "Opción no válida" ;;
    esac
done

#!/bin/bash

instalar_servidor() {
    sudo dnf install -y vsftpd
    sudo systemctl enable vsftpd
    
    sudo bash -c 'cat <<EOF > /etc/vsftpd.conf
listen=NO
listen_ipv6=YES
anonymous_enable=YES
no_anon_password=YES
anon_root=/srv/ftp/general
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
user_sub_token=\$USER
local_root=/home/ftp_users/\$USER
EOF'

    sudo mkdir -p /srv/ftp/general
    sudo chmod 755 /srv/ftp/general
    
    sudo firewall-cmd --permanent --add-service=ftp
    sudo firewall-cmd --reload
    sudo setsebool -P ftpd_full_access 1
    
    sudo systemctl restart vsftpd
    echo "Servidor Fedora configurado y Firewall/SELinux actualizados."
}

crear_usuarios() {
    sudo groupadd -f reprobados
    sudo groupadd -f recursadores
    
    read -p "Cantidad de usuarios a crear: " n
    for (( i=1; i<=$n; i++ )); do
        read -p "Nombre de usuario $i: " username
        read -s -p "Contraseña: " password
        echo
        echo "Seleccione grupo: 1) reprobados 2) recursadores"
        read -p "Opción: " g_opt
        
        grupo="reprobados"
        [[ $g_opt == "2" ]] && grupo="recursadores"

        user_home="/home/ftp_users/$username"
        
        sudo mkdir -p /home/ftp_users
        sudo useradd -m -d "$user_home" -s /sbin/nologin "$username"
        echo "$username:$password" | sudo chpasswd
        sudo usermod -aG $grupo "$username"

        sudo mkdir -p "$user_home/general"
        sudo mkdir -p "$user_home/$grupo"
        sudo mkdir -p "$user_home/$username"

        sudo mount --bind /srv/ftp/general "$user_home/general"
        
        sudo chown -R "$username:$username" "$user_home/$username"
        sudo chown "root:$grupo" "$user_home/$grupo"
        sudo chmod 775 "$user_home/$grupo"
        
        echo "Usuario $username listo."
    done
}

while true; do
    echo "=============================="
    echo "   GESTOR FTP FEDORA"
    echo "=============================="
    echo "1. Instalar y configurar vsftpd"
    echo "2. Crear usuarios y carpetas"
    echo "3. Salir"
    read -p "Seleccione una opción: " opcion
    case $opcion in
        1) instalar_servidor ;;
        2) crear_usuarios ;;
        3) exit ;;
        *) echo "Opción no válida" ;;
    esac
done

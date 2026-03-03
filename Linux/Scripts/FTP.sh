#!/bin/bash

instalar_servidor() {
    sudo dnf install -y vsftpd
    sudo systemctl enable vsftpd
    sudo mkdir -p /srv/ftp/general
    sudo mkdir -p /srv/ftp/reprobados
    sudo mkdir -p /srv/ftp/recursadores
    
    sudo chmod 777 /srv/ftp/general
    sudo chmod 770 /srv/ftp/reprobados
    sudo chmod 770 /srv/ftp/recursadores

    sudo bash -c 'cat <<EOF > /etc/vsftpd.conf
listen=NO
listen_ipv6=YES
anonymous_enable=YES
no_anon_password=YES
anon_root=/srv/ftp/general
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=/home/ftp_users/\$USER
pasv_min_port=30000
pasv_max_port=30100
EOF'
    sudo firewall-cmd --permanent --add-service=ftp
    sudo firewall-cmd --permanent --add-port=30000-30100/tcp
    sudo firewall-cmd --reload
    sudo setsebool -P ftpd_full_access 1
    sudo systemctl restart vsftpd
}

crear_usuarios() {
    sudo groupadd -f reprobados
    sudo groupadd -f recursadores
    read -p "Número de usuarios: " n
    for (( i=1; i<=$n; i++ )); do
        read -p "Usuario: " user
        read -s -p "Password: " pass; echo
        read -p "Grupo (1:reprobados, 2:recursadores): " g
        grp="reprobados"; [ "$g" == "2" ] && grp="recursadores"

        u_home="/home/ftp_users/$user"
        sudo useradd -m -d "$u_home" -s /sbin/nologin "$user" 2>/dev/null
        echo "$user:$pass" | sudo chpasswd
        sudo usermod -aG "$grp" "$user"

        sudo mkdir -p "$u_home/general" "$u_home/$grp" "$u_home/$user"
        
        sudo mount --bind /srv/ftp/general "$u_home/general"
        sudo mount --bind /srv/ftp/"$grp" "$u_home/$grp"
        
        sudo chown "$user":"$user" "$u_home/$user"
        sudo chown root:"$grp" /srv/ftp/"$grp"
        sudo chmod 770 /srv/ftp/"$grp"
    done
}

cambiar_grupo() {
    read -p "Usuario a mover: " user
    read -p "Nuevo grupo (1:reprobados, 2:recursadores): " g
    new_grp="reprobados"; [ "$g" == "2" ] && new_grp="recursadores"
    old_grp=$(groups "$user" | awk '{print $4}')

    sudo gpasswd -d "$user" "$old_grp" 2>/dev/null
    sudo usermod -aG "$new_grp" "$user"
    
    u_home="/home/ftp_users/$user"
    sudo umount "$u_home/$old_grp" 2>/dev/null
    sudo rm -rf "$u_home/$old_grp"
    sudo mkdir -p "$u_home/$new_grp"
    sudo mount --bind /srv/ftp/"$new_grp" "$u_home/$new_grp"
    echo "Usuario movido a $new_grp"
}

visualizar() {
    echo "--- Usuarios por Grupo ---"
    grep -E 'reprobados|recursadores' /etc/group
}

while true; do
    echo -e "\n1.Instalar 2.Crear 3.Cambiar Grupo 4.Ver 5.Salir"
    read -p "Opción: " o
    case $o in
        1) instalar_servidor ;;
        2) crear_usuarios ;;
        3) cambiar_grupo ;;
        4) visualizar ;;
        5) exit ;;
    esac
done

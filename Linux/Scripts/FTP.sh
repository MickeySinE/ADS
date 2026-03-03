#!/bin/bash

function inicializar_entorno() {
    echo "[+] Preparando dependencias y estructura base..."
    sudo dnf install -y vsftpd util-linux acl &>/dev/null

    sudo mkdir -p /srv/ftp/{general,anonimo/general,grupos/reprobados,grupos/recursadores}
    
    if ! mountpoint -q /srv/ftp/anonimo/general; then
        sudo mount --bind /srv/ftp/general /srv/ftp/anonimo/general
        sudo mount -o remount,ro,bind /srv/ftp/anonimo/general
    fi

    sudo groupadd -f reprobados
    sudo groupadd -f recursadores
    sudo groupadd -f ftp-users

    sudo chown -R root:ftp-users /srv/ftp/general
    sudo chmod 775 /srv/ftp/general
    sudo setfacl -R -d -m g:ftp-users:rwx /srv/ftp/general

    cat <<EOF | sudo tee /etc/vsftpd/vsftpd.conf > /dev/null
anonymous_enable=YES
no_anon_password=YES
anon_root=/srv/ftp/anonimo
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40010
listen=NO
listen_ipv6=YES
pam_service_name=vsftpd
user_sub_token=\$USER
local_root=/home/\$USER/ftp_root
EOF

    sudo firewall-cmd --permanent --add-service=ftp &>/dev/null
    sudo firewall-cmd --permanent --add-port=40000-40010/tcp &>/dev/null
    sudo firewall-cmd --reload &>/dev/null
    sudo setsebool -P ftpd_full_access on &>/dev/null
    
    sudo systemctl restart vsftpd
    sudo systemctl enable vsftpd &>/dev/null
    echo "[✓] Servidor configurado correctamente."
}

function gestionar_usuario() {
    local u=$1 p=$2 g=$3 accion=$4
    local h="/home/$u/ftp_root"

    if [ "$accion" == "crear" ]; then
        sudo useradd -m -g ftp-users -G "$g" -s /sbin/nologin "$u"
        echo "$u:$p" | sudo chpasswd
    else
        sudo usermod -G "$g" "$u"
        sudo umount "$h/reprobados" "$h/recursadores" "$h/general" 2>/dev/null
        sudo rm -rf "$h"
    fi

    sudo mkdir -p "$h/general" "$h/$g" "$h/$u"
    sudo mount --bind /srv/ftp/general "$h/general"
    sudo mount --bind /srv/ftp/grupos/"$g" "$h/$g"
    
    sudo chown "$u":"$g" "$h/$u"
    sudo chmod 700 "$h/$u"
    sudo setfacl -R -m g:"$g":rwx /srv/ftp/grupos/"$g"
}

function listar_sistema() {
    echo -e "\n--- USUARIOS Y SEGMENTACIÓN ---"
    printf "%-15s | %-15s | %-15s\n" "USUARIO" "GRUPO" "ESTADO"
    echo "----------------------------------------------------"
    for user in $(awk -F: '$4 == '$(grep "^ftp-users:" /etc/group | cut -d: -f3)' {print $1}' /etc/passwd); do
        grp="Ninguno"; id "$user" | grep -q "reprobados" && grp="reprobados"
        id "$user" | grep -q "recursadores" && grp="recursadores"
        printf "%-15s | %-15s | %-15s\n" "$user" "$grp" "Activo"
    done
}

while true; do
    echo -e "\n1) Alta Masiva 2) Cambiar Grupo 3) Listar 4) Reset 0) Salir"
    read -p ">> " opt
    case $opt in
        1)
            read -p "Cantidad: " total
            for (( i=1; i<=$total; i++ )); do
                read -p "Nombre: " n; read -s -p "Clave: " c; echo
                read -p "Grupo (1:reprobados, 2:recursadores): " gsel
                [[ "$gsel" == "1" ]] && g="reprobados" || g="recursadores"
                gestionar_usuario "$n" "$c" "$g" "crear"
            done ;;
        2)
            read -p "Usuario: " n; read -p "Nuevo Grupo (1:reprobados, 2:recursadores): " gsel
            [[ "$gsel" == "1" ]] && g="reprobados" || g="recursadores"
            gestionar_usuario "$n" "" "$g" "modificar" ;;
        3) listar_sistema ;;
        4) inicializar_entorno ;;
        0) break ;;
    esac
done

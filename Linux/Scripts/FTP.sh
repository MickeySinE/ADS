#!/bin/bash

ROJO='\033[0;31m'
VERDE='\033[0;32m'
AZUL='\033[0;34m'
NC='\033[0m'

preparar_entorno_ftp() {
    sudo dnf install -y vsftpd util-linux acl &>/dev/null

    cat <<EOF | sudo tee /etc/vsftpd/vsftpd.conf > /dev/null
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
check_shell=NO
anon_root=/srv/ftp/anonymous
no_anon_password=YES
anon_world_readable_only=NO   
anon_enable=YES
anon_mkdir_write_enable=NO
anon_upload_enable=NO
anon_other_write_enable=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40010
listen=NO
listen_ipv6=YES
pam_service_name=vsftpd
EOF

    sudo mkdir -p /srv/ftp/{grupos/reprobados,grupos/recursadores,publico,anonymous/general,users}
    
    sudo chown root:root /srv/ftp/anonymous
    sudo chmod 555 /srv/ftp/anonymous

    if ! mountpoint -q /srv/ftp/anonymous/general; then
        sudo mount --bind /srv/ftp/publico /srv/ftp/anonymous/general
        sudo mount -o remount,ro,bind /srv/ftp/anonymous/general
    fi

    sudo groupadd -f reprobados
    sudo groupadd -f recursadores
    sudo groupadd -f grupo-ftp

    sudo chown root:grupo-ftp /srv/ftp/publico
    sudo chmod 775 /srv/ftp/publico
    
    sudo setfacl -R -m g:grupo-ftp:rwx /srv/ftp/publico
    sudo setfacl -R -d -m g:grupo-ftp:rwx /srv/ftp/publico

    sudo firewall-cmd --permanent --add-service=ftp &>/dev/null
    sudo firewall-cmd --permanent --add-port=40000-40010/tcp &>/dev/null
    sudo firewall-cmd --reload &>/dev/null

    sudo setsebool -P ftpd_full_access on &>/dev/null
    sudo setsebool -P tftp_home_dir on &>/dev/null
    
    if ! grep -q "/sbin/nologin" /etc/shells; then
        echo "/sbin/nologin" | sudo tee -a /etc/shells > /dev/null
    fi

    sudo systemctl restart vsftpd
    sudo systemctl enable vsftpd &>/dev/null
}

establecer_puntos_montaje() {
    local usuario=$1
    local grupo=$2
    local home_dir="/home/$usuario"

    sudo mkdir -p "$home_dir/general" "$home_dir/$grupo" "$home_dir/$usuario"

    sudo umount "$home_dir/general" 2>/dev/null
    sudo umount "$home_dir/reprobados" 2>/dev/null
    sudo umount "$home_dir/recursadores" 2>/dev/null

    sudo mount --bind /srv/ftp/publico "$home_dir/general"
    sudo mount --bind /srv/ftp/grupos/"$grupo" "$home_dir/$grupo"

    sudo chown "$usuario":"$grupo" "$home_dir/$usuario"
    sudo chmod 700 "$home_dir/$usuario"

    sudo chown root:"$grupo" /srv/ftp/grupos/"$grupo"
    sudo chmod 775 /srv/ftp/grupos/"$grupo"
    sudo setfacl -R -m g:"$grupo":rwx /srv/ftp/grupos/"$grupo"
    sudo setfacl -R -d -m g:"$grupo":rwx /srv/ftp/grupos/"$grupo"
}

dar_alta_usuario() {
    local user=$1
    local pass=$2
    local group=$3

    if id "$user" &>/dev/null; then
        echo -e "${ROJO}[!] El usuario $user ya existe.${NC}"
        return
    fi

    sudo useradd -m -g grupo-ftp -G "$group" -s /sbin/nologin "$user"
    echo "$user:$pass" | sudo chpasswd

    establecer_puntos_montaje "$user" "$group"
    echo -e "${VERDE}[✓] Usuario $user configurado.${NC}"
}

mover_usuario_grupo() {
    local user=$1
    local n_group=$2

    if ! id "$user" &>/dev/null; then
        echo -e "${ROJO}[!] Usuario no encontrado.${NC}"
        return
    fi

    sudo usermod -G "$n_group" "$user"
    
    sudo umount "/home/$user/reprobados" 2>/dev/null
    sudo umount "/home/$user/recursadores" 2>/dev/null
    sudo rm -rf "/home/$user/reprobados" "/home/$user/recursadores"

    establecer_puntos_montaje "$user" "$n_group"
    echo -e "${VERDE}[✓] Cambio de grupo y permisos aplicado.${NC}"
}

mostrar_resumen_usuarios() {
    echo -e "\n--- USUARIOS FTP ACTIVOS ---"
    printf "%-15s | %-15s\n" "USUARIO" "GRUPO"
    echo "---------------------------------"
    GID_FTP=$(grep "^grupo-ftp:" /etc/group | cut -d: -f3)
    [ -z "$GID_FTP" ] && return
    users_list=$(awk -F: -v gid="$GID_FTP" '$4 == gid {print $1}' /etc/passwd)
    for u in $users_list; do
        if id "$u" | grep -q "reprobados"; then gr="reprobados"; 
        elif id "$u" | grep -q "recursadores"; then gr="recursadores";
        else gr="Sin grupo"; fi
        printf "%-15s | %-15s\n" "$u" "$gr"
    done
}

diagnostico_sistema() {
    echo -e "\n--- ESTADO DEL SERVIDOR ---"
    systemctl is-active vsftpd
    ip_addr=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
    echo -e "IP: ${AZUL}$ip_addr${NC}"
    echo -n "Montaje Anónimo (Solo Lectura): "
    mountpoint -q /srv/ftp/anonymous/general && echo "OK" || echo "ERROR"
}

menu_principal() {
    if ! systemctl is-active --quiet vsftpd; then
        preparar_entorno_ftp
    fi

    while true; do
        echo -e "\n${AZUL}======================================="
        echo "      GESTOR FTP AUTOMATIZADO"
        echo -e "=======================================${NC}"
        echo "1) Registro masivo"
        echo "2) Cambiar grupo"
        echo "3) Ver usuarios"
        echo "4) Diagnóstico"
        echo "5) Resetear Servicio"
        echo "0) Salir"
        echo "---------------------------------------"
        read -p "Opción: " opt

        case $opt in
            1)
                read -p "Cantidad: " total
                for (( i=1; i<=$total; i++ )); do
                    read -p "Username: " u_name
                    read -s -p "Password: " u_pass; echo
                    read -p "Grupo (1:reprobados, 2:recursadores): " u_group
                    [[ "$u_group" == "1" ]] && grp="reprobados" || grp="recursadores"
                    dar_alta_usuario "$u_name" "$u_pass" "$grp"
                done
                ;;
            2)
                read -p "Usuario: " u_name
                read -p "Nuevo Grupo (1:reprobados, 2:recursadores): " u_group
                [[ "$u_group" == "1" ]] && grp="reprobados" || grp="recursadores"
                mover_usuario_grupo "$u_name" "$grp"
                ;;
            3) mostrar_resumen_usuarios ;;
            4) diagnostico_sistema ;;
            5) preparar_entorno_ftp ;;
            0) exit 0 ;;
            *) echo "Inválido" ;;
        esac
        read -p "Enter para continuar..."
    done
}

menu_principal

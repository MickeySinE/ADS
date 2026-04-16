#!/bin/bash

# =========================================================
# VARIABLES DE CONFIGURACIÓN (Ajusta la IP si es necesario)
# =========================================================
DOMINIO="reprobados.com"
DOMINIO_UPPER="REPROBADOS.COM"
DC_IP="192.168.100.20"  # <--- Verifica que esta sea la IP de tu Windows Server
ADMIN_USER="Administrator"
ADMIN_PASS="Admin12345!"

if [ "$EUID" -ne 0 ]; then
    echo "[!] Ejecuta como root: sudo bash unir_dominio.sh"
    exit 1
fi

echo "========================================="
echo "   UNION AL DOMINIO: $DOMINIO"
echo "========================================="

# 1. Limpieza de instalaciones previas de SSSD para evitar conflictos
systemctl stop sssd 2>/dev/null
rm -rf /var/lib/sss/db/* /var/lib/sss/mc/*

# 2. Configuración de DNS
echo "[*] Configurando DNS..."
# Quitamos el atributo de solo lectura por si acaso existía
chattr -i /etc/resolv.conf 2>/dev/null
cat > /etc/resolv.conf << RESOLVEOF
nameserver $DC_IP
search $DOMINIO
RESOLVEOF
# Opcional: proteger el archivo para que NetworkManager no lo sobrescriba
# chattr +i /etc/resolv.conf 
echo "[OK] DNS configurado para apuntar a $DC_IP"

# 3. Instalación de dependencias
echo "[*] Instalando paquetes necesarios..."
apt update
DEBIAN_FRONTEND=noninteractive apt install -yq realmd sssd sssd-tools adcli krb5-user packagekit oddjob oddjob-mkhomedir
echo "[OK] Paquetes instalados."

# 4. Unión al Dominio
echo "[*] Uniéndose al dominio $DOMINIO..."
# Usamos echo para pasar la contraseña automáticamente
echo "$ADMIN_PASS" | realm join --user=$ADMIN_USER $DOMINIO
if [ $? -ne 0 ]; then
    echo "[!] Error al unirse al dominio. Revisa conectividad y contraseña."
    exit 1
fi
echo "[OK] Unido al dominio exitosamente."

# 5. Configuración de SSSD (Personalizado para tu práctica)
echo "[*] Configurando /etc/sssd/sssd.conf..."
cat > /etc/sssd/sssd.conf << SSSDEOF
[sssd]
domains = $DOMINIO
config_file_version = 2
services = nss, pam

[domain/$DOMINIO]
ad_domain = $DOMINIO
krb5_realm = $DOMINIO_UPPER
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
default_shell = /bin/bash
ldap_id_mapping = True

# Requerido por tu práctica:
use_fully_qualified_names = True
fallback_homedir = /home/%u@%d

# IMPORTANTE: Para que funcionen las Logon Hours (GPO)
access_provider = ad
ad_gpo_access_control = enforcing
SSSDEOF

chmod 600 /etc/sssd/sssd.conf
systemctl enable sssd
systemctl restart sssd
echo "[OK] sssd configurado y reiniciado."

# 6. Creación automática de Home Directory
echo "[*] Habilitando creación de carpetas personales..."
pam-auth-update --enable mkhomedir
echo "[OK] mkhomedir habilitado."

# 7. Configuración de SUDO (Punto clave de la rúbrica)
echo "[*] Configurando permisos de sudo para usuarios de AD..."
# Escapamos el espacio y usamos comillas para el grupo "Domain Users"
cat > /etc/sudoers.d/ad-admins << SUDOEOF
"%domain users@$DOMINIO" ALL=(ALL) ALL
SUDOEOF
chmod 440 /etc/sudoers.d/ad-admins
echo "[OK] Sudoers configurado."

echo "========================================="
echo "        VERIFICACIÓN FINAL"
echo "========================================="
# Esperar un momento a que SSSD sincronice
sleep 3
id "maria@$DOMINIO" && echo "[GANASTE] Maria encontrada." || echo "[!] Maria no aparece, revisa logs: journalctl -u sssd"

echo "Logueate con: su - maria@$DOMINIO"

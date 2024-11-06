#!/bin/bash

# Variables
DOMAIN="jdtech.com.co"
HOSTNAME="mails.$DOMAIN"
MYSQL_ROOT_PASS="mailpassword"  # Usa la misma contraseña que ya tienes para MySQL

# Colores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Función para imprimir mensajes
print_message() {
    echo -e "${GREEN}[+] $1${NC}"
}

print_error() {
    echo -e "${RED}[-] $1${NC}"
    exit 1
}

# Verificar si es root
if [ "$EUID" -ne 0 ]; then 
    print_error "Por favor ejecuta el script como root"
fi

print_message "Iniciando instalación de ISPConfig..."

# Actualizar sistema
print_message "Actualizando el sistema..."
apt-get update -y
apt-get upgrade -y

# Instalar dependencias
print_message "Instalando dependencias..."
apt-get install -y \
    apache2 \
    php \
    php-mysql \
    php-curl \
    php-gd \
    php-json \
    php-zip \
    php-xml \
    php-mbstring \
    php-soap \
    php-intl \
    mcrypt \
    wget \
    unzip \
    tar

# Descargar ISPConfig
print_message "Descargando ISPConfig..."
cd /tmp
wget https://ispconfig.org/downloads/ISPConfig-3-stable.tar.gz
tar xfz ISPConfig-3-stable.tar.gz
cd ispconfig3_install/install/

# Crear archivo de autoinstalación
print_message "Configurando instalación automática..."
cat > autoinstall.ini << EOF
[install]
language=en
install_mode=standard
hostname=$HOSTNAME
mysql_hostname=localhost
mysql_root_user=root
mysql_root_password=$MYSQL_ROOT_PASS
mysql_database=dbispconfig
mysql_charset=utf8
http_server=apache
timezone=America/Bogota
web_server=apache
php_version=7.4
webmail_server=roundcube

[ssl_cert]
ssl_cert_country=CO
ssl_cert_state=Colombia
ssl_cert_locality=Bogota
ssl_cert_organisation=ISPConfig
ssl_cert_organisation_unit=IT
ssl_cert_common_name=$HOSTNAME

[admin]
default_theme=default

[services]
mail_server=yes
web_server=yes
dns_server=yes
file_server=no
db_server=yes
vserver_server=no
proxy_server=no
firewall_server=no

[mail]
mailbox_location=/var/vmail/
mailbox_format=maildir
homedir_path=/var/vmail
dkim_path=/var/lib/amavis/dkim
EOF

# Iniciar instalación
print_message "Iniciando instalación de ISPConfig..."
php -q install.php --autoinstall=autoinstall.ini

print_message "=== Instalación completada ==="
print_message ""
print_message "Para acceder a ISPConfig:"
print_message "1. Abre https://$HOSTNAME:8080"
print_message "2. Usuario: admin"
print_message "3. Contraseña: admin (¡cámbiala inmediatamente!)"
print_message ""
print_message "Importante:"
print_message "1. Ve a System -> Interface Config"
print_message "2. En la pestaña Mail, verifica que esté configurado para usar tu Postfix/Dovecot existente"
print_message "3. Los usuarios de correo se pueden gestionar en Mail -> Email Accounts"
print_message ""
print_message "Logs:"
print_message "tail -f /var/log/ispconfig/ispconfig.log"
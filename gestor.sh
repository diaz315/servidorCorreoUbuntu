#!/bin/bash

# Variables
DOMAIN="jdtech.com.co"
HOSTNAME="mails.$DOMAIN"
POSTFIX_DB_PASS="UnaNuevaContraseña"
ADMIN_EMAIL="admin@$DOMAIN"
VERSION="3.3.13"
ADMIN_PASS="mailpassword"

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

print_message "Iniciando instalación de PostfixAdmin $VERSION con Apache2..."

# Actualizar sistema
print_message "Actualizando el sistema..."
apt-get update -y
apt-get upgrade -y

# Instalar dependencias
print_message "Instalando dependencias..."
apt-get install -y apache2 libapache2-mod-php \
    php php-cli php-imap php-json \
    php-mysql php-opcache php-mbstring \
    php-zip php-xml php-pdo php-common \
    php-pdo-mysql php-curl php-gd \
    unzip wget

# Descargar y configurar PostfixAdmin
print_message "Descargando PostfixAdmin..."
cd /tmp
wget -q https://github.com/postfixadmin/postfixadmin/archive/postfixadmin-${VERSION}.zip
unzip postfixadmin-${VERSION}.zip

# Hacer backup si existe una instalación anterior
if [ -d "/var/www/html/postfixadmin" ]; then
    print_message "Haciendo backup de la instalación anterior..."
    mv /var/www/html/postfixadmin "/var/www/html/postfixadmin.bak.$(date +%Y%m%d)"
fi

mv postfixadmin-postfixadmin-${VERSION} /var/www/html/postfixadmin
rm postfixadmin-${VERSION}.zip

# Configurar permisos
print_message "Configurando permisos..."
mkdir -p /var/www/html/postfixadmin/templates_c
chown -R www-data:www-data /var/www/html/postfixadmin
chmod -R 755 /var/www/html/postfixadmin
chmod -R 777 /var/www/html/postfixadmin/templates_c

# Crear configuración de PostfixAdmin
print_message "Creando archivo de configuración..."
cat > /var/www/html/postfixadmin/config.local.php << EOF
<?php
\$CONF['configured'] = true;

\$CONF['database_type'] = 'mysqli';
\$CONF['database_host'] = '127.0.0.1';
\$CONF['database_user'] = 'postfix';
\$CONF['database_password'] = '$POSTFIX_DB_PASS';
\$CONF['database_name'] = 'mailserver';

\$CONF['default_aliases'] = array (
    'abuse' => 'abuse@$DOMAIN',
    'hostmaster' => 'hostmaster@$DOMAIN',
    'postmaster' => 'postmaster@$DOMAIN',
    'webmaster' => 'webmaster@$DOMAIN'
);

\$CONF['fetchmail'] = 'NO';
\$CONF['show_footer_text'] = 'NO';

\$CONF['quota'] = 'YES';
\$CONF['domain_quota'] = 'YES';
\$CONF['quota_multiplier'] = '1024000';
\$CONF['used_quotas'] = 'YES';
\$CONF['new_quota_table'] = 'YES';

\$CONF['aliases'] = '0';
\$CONF['mailboxes'] = '0';
\$CONF['maxquota'] = '0';
\$CONF['domain_quota_default'] = '0';
\$CONF['encrypt'] = 'dovecot:SHA512-CRYPT';
\$CONF['default_language'] = 'es';
\$CONF['admin_email'] = '$ADMIN_EMAIL';
\$CONF['footer_text'] = 'Return to webmail';
\$CONF['footer_link'] = 'https://$HOSTNAME/roundcube';

// Configuraciones adicionales
\$CONF['smtp_server'] = 'localhost';
\$CONF['smtp_port'] = '25';
\$CONF['authlib_default_flavor'] = 'md5raw';
\$CONF['dovecotpw'] = "/usr/bin/doveadm pw";
\$CONF['min_password_length'] = 8;
\$CONF['generate_password'] = 'NO';
\$CONF['show_password'] = 'NO';
\$CONF['page_size'] = '10';
\$CONF['default_aliases_domain'] = array (
    'abuse' => 'abuse@$DOMAIN',
    'hostmaster' => 'hostmaster@$DOMAIN',
    'postmaster' => 'postmaster@$DOMAIN',
    'webmaster' => 'webmaster@$DOMAIN'
);
EOF

# Configurar PHP
print_message "Configurando PHP..."
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
PHP_INI_PATH="/etc/php/$PHP_VERSION/apache2/php.ini"

# Ajustar configuración de PHP
sed -i 's/;date.timezone =/date.timezone = America\/Bogota/' $PHP_INI_PATH
sed -i 's/memory_limit = .*/memory_limit = 256M/' $PHP_INI_PATH
sed -i 's/post_max_size = .*/post_max_size = 64M/' $PHP_INI_PATH
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' $PHP_INI_PATH

# Configurar Apache
print_message "Configurando Apache..."
cat > /etc/apache2/sites-available/postfixadmin.conf << EOF
<VirtualHost *:80>
    ServerName $HOSTNAME
    DocumentRoot /var/www/html/postfixadmin/public
    
    Alias /postfixadmin /var/www/html/postfixadmin/public

    <Directory /var/www/html/postfixadmin/public>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        
        <FilesMatch ".php$">
            Require all granted
        </FilesMatch>
    </Directory>
    
    <DirectoryMatch "/var/www/html/postfixadmin/(templates_c|templates|vendor)">
        Require all denied
    </DirectoryMatch>

    ErrorLog \${APACHE_LOG_DIR}/postfixadmin_error.log
    CustomLog \${APACHE_LOG_DIR}/postfixadmin_access.log combined

    <FilesMatch \.php$>
        SetHandler application/x-httpd-php
    </FilesMatch>
</VirtualHost>
EOF

# Habilitar módulos de Apache necesarios
print_message "Habilitando módulos de Apache..."
a2enmod rewrite
a2enmod ssl
a2enmod headers

# Habilitar el sitio
print_message "Habilitando sitio en Apache..."
a2ensite postfixadmin
a2dissite 000-default

# Verificar configuración de Apache
apache2ctl configtest || print_error "Error en la configuración de Apache"

# Ejecutar el script de actualización de la base de datos
print_message "Actualizando base de datos..."
sudo -u www-data php /var/www/html/postfixadmin/public/upgrade.php

# Crear superadmin
print_message "Creando superadmin..."
cd /var/www/html/postfixadmin/scripts
echo "Configurando superadmin..."
php postfixadmin-cli admin add --superadmin --email=$ADMIN_EMAIL --password=$ADMIN_PASS --password2=$ADMIN_PASS --active --domain=$DOMAIN

# Reiniciar servicios
print_message "Reiniciando servicios..."
systemctl restart apache2

print_message "=== Instalación completada ==="
print_message "Accede a http://$HOSTNAME/postfixadmin"
print_message ""
print_message "Usuario: $ADMIN_EMAIL"
print_message "Contraseña: $ADMIN_PASS"
print_message ""
print_message "Para verificar los módulos PHP instalados:"
print_message "php -m | grep pdo"
print_message ""
print_message "Verifica los logs de Apache con:"
print_message "tail -f /var/log/apache2/postfixadmin_error.log"
print_message ""
print_message "Para habilitar SSL, ejecuta:"
print_message "certbot --apache -d $HOSTNAME"
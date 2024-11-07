#!/bin/bash

# Variables
SERVER_IP="159.223.102.84"
DOMAIN="jdtech.com.co"
HOSTNAME="mail.$DOMAIN"
MYSQL_POSTFIX_PASS="201849041"
MYSQL_ADMIN_PASS="20184904"
DES_KEY=$(openssl rand -base64 18)
SETUP_PASSWORD="admin123"

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
}

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then 
    print_error "Por favor ejecuta el script como root"
    exit 1
fi

# Preconfigurar Postfix para instalación no interactiva
print_message "Preconfigurando Postfix..."
debconf-set-selections <<< "postfix postfix/mailname string $HOSTNAME"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
debconf-set-selections <<< "postfix postfix/destinations string $HOSTNAME, $DOMAIN, localhost.localdomain, localhost"

# Preconfigurar Roundcube para instalación no interactiva
debconf-set-selections <<< "roundcube-core roundcube/dbconfig-install boolean true"
debconf-set-selections <<< "roundcube-core roundcube/database-type select mysql"
debconf-set-selections <<< "roundcube-core roundcube/mysql/admin-pass password $MYSQL_ADMIN_PASS"
debconf-set-selections <<< "roundcube-core roundcube/db/dbname string roundcube"
debconf-set-selections <<< "roundcube-core roundcube/db/user string roundcube"

# 1. Preparación del Sistema
print_message "Actualizando el sistema..."
DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y

print_message "Instalando paquetes necesarios..."
DEBIAN_FRONTEND=noninteractive apt install -y \
    postfix postfix-mysql dovecot-core dovecot-imapd dovecot-pop3d \
    dovecot-lmtpd dovecot-mysql mysql-server swaks \
    roundcube roundcube-mysql roundcube-core \
    php-zip php-imagick php-mysql php-xml php-mbstring php-curl roundcube-plugins \
    postfixadmin php-imap apache2 \
    php-pgsql \
    php-sqlite3

SETUP_PASSWORD_HASH=$(php -r "echo password_hash('$SETUP_PASSWORD', PASSWORD_DEFAULT);")

# Configurar hostname
print_message "Configurando hostname..."
hostnamectl set-hostname $HOSTNAME

# Actualizar /etc/hosts
print_message "Actualizando /etc/hosts..."
echo "$SERVER_IP $HOSTNAME mail" >> /etc/hosts

# 2. Configuración de MySQL
print_message "Configurando MySQL..."
mysql -e "CREATE DATABASE IF NOT EXISTS postfixadmin;"

# Crear usuarios con mysql_native_password

mysql -e "CREATE USER IF NOT EXISTS 'postfixadmin'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_POSTFIX_PASS';"

# Asignar permisos
mysql -e "GRANT ALL PRIVILEGES ON postfixadmin.* TO 'postfixadmin'@'localhost';"

# Asegurar el método de autenticación con ALTER USER
mysql -e "ALTER USER 'postfixadmin'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_POSTFIX_PASS';"

mysql -e "FLUSH PRIVILEGES;"

# Configuración de PostfixAdmin
print_message "Configurando PostfixAdmin..."
cat > /etc/postfixadmin/config.local.php << EOF
<?php
\$CONF['database_type'] = 'mysqli';
\$CONF['database_host'] = 'localhost';
\$CONF['database_user'] = 'postfixadmin';
\$CONF['database_password'] = '$MYSQL_POSTFIX_PASS';
\$CONF['database_name'] = 'postfixadmin';
\$CONF['configured'] = true;
\$CONF['setup_password'] = '$SETUP_PASSWORD_HASH';
\$CONF['default_language'] = 'es';
\$CONF['domain_path'] = 'YES';
\$CONF['domain_in_mailbox'] = 'YES';
\$CONF['fetchmail'] = 'NO';
\$CONF['show_footer_text'] = 'NO';
\$CONF['smtp_server'] = 'localhost';
\$CONF['smtp_port'] = '25';
\$CONF['encrypt'] = 'md5crypt';
\$CONF['dovecotpw'] = "/usr/bin/doveadm pw -s SHA512-CRYPT";
EOF


# Configurar Apache Virtual Hosts
print_message "Configurando Virtual Hosts de Apache..."
cat > /etc/apache2/sites-available/000-default.conf << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    ServerName $DOMAIN
    DocumentRoot /var/www/html

    # Configuración para PostfixAdmin
    Alias /postfixadmin /usr/share/postfixadmin/public
    <Directory /usr/share/postfixadmin/public>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    # Configuración para Roundcube
    Alias /webmail /var/lib/roundcube
    <Directory /var/lib/roundcube>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>

<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    ServerName admin.$DOMAIN
    DocumentRoot /usr/share/postfixadmin/public

    <Directory /usr/share/postfixadmin/public>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/postfixadmin_error.log
    CustomLog \${APACHE_LOG_DIR}/postfixadmin_access.log combined
</VirtualHost>

<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    ServerName mail.$DOMAIN
    DocumentRoot /var/lib/roundcube

    <Directory /var/lib/roundcube>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog \${APACHE_LOG_DIR}/roundcube_access.log combined
</VirtualHost>
EOF

# Habilitar módulos de Apache necesarios
print_message "Habilitando módulos de Apache..."
a2enmod rewrite
a2enmod headers
a2enmod ssl

# Crear directorio templates_c para PostfixAdmin
mkdir -p /var/lib/postfixadmin/templates_c
chown -R www-data:www-data /var/lib/postfixadmin
chmod -R 755 /var/lib/postfixadmin

# Ejecutar setup.php de PostfixAdmin
php /usr/share/postfixadmin/public/setup.php

# 3. Configuración de Postfix
print_message "Configurando Postfix..."

cat > /etc/postfix/main.cf << EOF
# Basic Configuration
smtpd_banner = \$myhostname ESMTP \$mail_name
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 3.6

# Hostname and Domain Configuration
myhostname = $HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain
mydestination = localhost
relayhost =

# Network Configuration
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
inet_interfaces = all
inet_protocols = all

# Virtual Domain and Mailbox Configuration
virtual_mailbox_domains = mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf
virtual_mailbox_maps = mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf
virtual_transport = lmtp:unix:private/dovecot-lmtp

virtual_mailbox_base = /var/mail/vhosts
virtual_minimum_uid = 5000
virtual_uid_maps = static:5000
virtual_gid_maps = static:5000

# Message Size and Delimiter
mailbox_size_limit = 0
recipient_delimiter = +

# SASL Authentication
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = \$myhostname
broken_sasl_auth_clients = yes

# TLS Configuration
smtpd_tls_cert_file = /etc/postfix/ssl/smtp.crt
smtpd_tls_key_file = /etc/postfix/ssl/smtp.key
smtpd_tls_security_level = may
smtpd_tls_auth_only = no
smtp_tls_security_level = may
smtp_tls_loglevel = 1

# SMTP Restrictions
smtpd_recipient_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_unauth_destination

smtpd_relay_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_unauth_destination

# Additional Security Settings
smtpd_helo_required = yes
disable_vrfy_command = yes

# Additional Settings
smtpd_delay_reject = yes
smtpd_helo_restrictions =
    permit_mynetworks,
    reject_invalid_helo_hostname,
    reject_non_fqdn_helo_hostname

smtpd_sender_restrictions =
    permit_mynetworks,
    reject_non_fqdn_sender,
    reject_unknown_sender_domain

# Performance Tuning
default_process_limit = 100
smtp_destination_concurrency_limit = 2
smtp_destination_rate_delay = 1s
local_destination_concurrency_limit = 2

# Queue Settings
maximal_queue_lifetime = 1d
bounce_queue_lifetime = 1d
EOF

# Configuración MySQL para Postfix
cat > /etc/postfix/mysql-virtual-mailbox-domains.cf << EOF
user = postfixadmin
password = $MYSQL_POSTFIX_PASS
hosts = 127.0.0.1
dbname = postfixadmin
query = SELECT domain FROM domain WHERE domain='%s' AND active = '1'
EOF

cat > /etc/postfix/mysql-virtual-mailbox-maps.cf << EOF
user = postfixadmin
password = $MYSQL_POSTFIX_PASS
hosts = 127.0.0.1
dbname = postfixadmin
query = SELECT maildir FROM mailbox WHERE username='%s' AND active = '1'
EOF

# 4. Configuración de Dovecot
print_message "Configurando Dovecot..."
cat > /etc/dovecot/dovecot.conf << EOF
protocols = imap pop3 lmtp
listen = *

mail_location = maildir:/var/mail/vhosts/%d/%n
mail_privileged_group = mail

namespace inbox {
    inbox = yes
    separator = /
    mailbox Drafts {
        auto = subscribe
        special_use = \Drafts
    }
    mailbox Sent {
        auto = subscribe
        special_use = \Sent
    }
    mailbox Trash {
        auto = subscribe
        special_use = \Trash
    }
    mailbox Junk {
        auto = subscribe
        special_use = \Junk
    }
}

service lmtp {
    unix_listener /var/spool/postfix/private/dovecot-lmtp {
        group = postfix
        mode = 0600
        user = postfix
    }
}

service auth {
    unix_listener /var/spool/postfix/private/auth {
        mode = 0666
        user = postfix
        group = postfix
    }
}

auth_mechanisms = plain login
disable_plaintext_auth = no

passdb {
    driver = sql
    args = /etc/dovecot/dovecot-sql.conf.ext
}

userdb {
    driver = static
    args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
}
EOF

cat > /etc/dovecot/dovecot-sql.conf.ext << EOF
driver = mysql
connect = host=localhost dbname=postfixadmin user=postfixadmin password=$MYSQL_POSTFIX_PASS
default_pass_scheme = SHA512-CRYPT

password_query = SELECT username as user, password, \
    concat('/var/mail/vhosts/',domain,'/',username) as userdb_home, \
    5000 as userdb_uid, 5000 as userdb_gid \
    FROM mailbox WHERE username = '%u' AND active = '1'

user_query = SELECT concat('/var/mail/vhosts/',domain,'/',username) as home, \
    5000 AS uid, 5000 AS gid \
    FROM mailbox WHERE username = '%u' AND active = '1'

iterate_query = SELECT username AS user FROM mailbox WHERE active = '1'
EOF

cat > /etc/dovecot/conf.d/10-auth.conf << EOF
disable_plaintext_auth = no
auth_mechanisms = plain login
!include auth-sql.conf.ext
EOF

# 5. Configuración de Roundcube
print_message "Configurando Roundcube..."


# Configure Postfix master.cf ---> Para indicarle a roundcube el puerto puerto de submission (587) y SMTPS (465), para poder enviar
cat > /etc/postfix/master.cf << 'EOL'
# SMTP server
smtp      inet  n       -       y       -       -       smtpd

# SMTP submission
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=may
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_tls_auth_only=no
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

# SMTPS submission (port 465)
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

# Postfix services
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -      y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
  -o syslog_name=postfix/$service_name
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
postlog   unix-dgram n  -       n       -       1       postlogd
EOL

chmod 755 /usr/bin/doveadm
chown root:root /usr/bin/doveadm
setcap cap_setuid=ep /usr/bin/doveadm

cat > /etc/roundcube/config.inc.php << EOL
<?php
    \$config = [];
    include("/etc/roundcube/debian-db-roundcube.php");
    \$config['imap_host'] = ["localhost:143"];
    \$config['smtp_host'] = 'localhost:587';
    \$config['smtp_auth_type'] = 'PLAIN';
    \$config['smtp_helo_host'] = '$DOMAIN';
    \$config['default_host'] = 'localhost';
    \$config['smtp_server'] = 'localhost';
    \$config['smtp_port'] = 25;
    \$config['smtp_user'] = '%u';
    \$config['smtp_pass'] = '%p';
    \$config['support_url'] = '';
    \$config['product_name'] = 'Webmail';
    \$config['des_key'] = '$DES_KEY';
    \$config['skin'] = 'elastic';
    \$config['plugins'] = array();
    \$config['language'] = 'es_ES';
    \$config['imap_conn_options'] = array(
        'ssl' => array(
            'verify_peer' => false,
            'verify_peer_name' => false,
        ),
    );
    \$config['smtp_conn_options'] = array(
        'ssl' => array(
            'verify_peer' => false,
            'verify_peer_name' => false,
        ),
    );

    // Configuraciones predeterminadas
    \$config['prefer_html'] = true;
    \$config['htmleditor'] = true;
    \$config['prettydate'] = true;
    \$config['preview_pane'] = true;
    \$config['message_show_email'] = true;
    \$config['timezone'] = 'America/Bogota';
EOL

# 6. Crear usuario virtual mail
print_message "Creando usuario virtual mail..."
groupadd -g 5000 vmail
useradd -g vmail -u 5000 vmail -d /var/mail
mkdir -p /var/mail/vhosts
chown -R vmail:vmail /var/mail/vhosts
chmod -R 700 /var/mail/vhosts

# 7. Generar certificado SSL
print_message "Generando certificado SSL..."
mkdir -p /etc/postfix/ssl
openssl req -new -x509 -days 365 -nodes \
    -out /etc/postfix/ssl/smtp.crt \
    -keyout /etc/postfix/ssl/smtp.key \
    -subj "/C=CO/ST=State/L=City/O=Organization/CN=$DOMAIN"

# 8. Establecer permisos
print_message "Estableciendo permisos..."
chmod 0640 /etc/postfix/mysql-*
chown root:postfix /etc/postfix/mysql-*
chmod 600 /etc/postfix/ssl/*
chown postfix:postfix /etc/postfix/ssl/*
chown -R www-data:www-data /var/lib/roundcube
chown -R www-data:www-data /etc/roundcube
chmod -R 755 /var/lib/roundcube
chmod -R 755 /etc/roundcube

# 9. Configurar Apache
print_message "Configurando Apache..."
a2enconf roundcube

# 10. Reiniciar servicios
print_message "Reiniciando servicios..."
systemctl restart mysql
systemctl restart postfix
systemctl restart dovecot
systemctl restart apache2

systemctl enable mysql postfix dovecot apache2

# 11. Verificación final
print_message "Verificando servicios..."
if systemctl is-active --quiet mysql && \
   systemctl is-active --quiet postfix && \
   systemctl is-active --quiet dovecot && \
   systemctl is-active --quiet apache2; then
    print_message "Todos los servicios están funcionando correctamente"
else
    print_error "Algunos servicios no están funcionando correctamente"
    print_message "Por favor, verifica los logs en /var/log/mail.log"
fi

#!/bin/bash

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
}

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then 
    print_error "Por favor ejecuta el script como root"
    exit 1
fi

print_message "Corrigiendo permisos y configuración de Roundcube..."

# 1. Corregir permisos de directorios de Roundcube
print_message "Ajustando permisos de directorios..."
chown -R www-data:www-data /var/lib/roundcube
chown -R www-data:www-data /etc/roundcube
chmod -R 755 /var/lib/roundcube
chmod -R 755 /etc/roundcube

# 2. Asegurar que los enlaces simbólicos están correctos
print_message "Verificando enlaces simbólicos..."
if [ ! -L /var/lib/roundcube/program/js ]; then
    ln -sf /usr/share/roundcube/program/js /var/lib/roundcube/program/js
fi

if [ ! -L /var/lib/roundcube/program/skins ]; then
    ln -sf /usr/share/roundcube/program/skins /var/lib/roundcube/program/skins
fi

# 3. Configurar Apache para servir archivos estáticos
print_message "Configurando Apache para archivos estáticos..."
cat > /etc/apache2/conf-available/roundcube.conf << EOF
Alias /webmail /var/lib/roundcube

<Directory /var/lib/roundcube>
    Options FollowSymLinks
    AllowOverride All
    Require all granted

    <IfModule mod_php.c>
        php_flag register_globals off
        php_flag magic_quotes_gpc off
        php_flag magic_quotes_runtime off
        php_flag mbstring.func_overload off
        php_flag suhosin.session.encrypt off
    </IfModule>

    <IfModule mod_rewrite.c>
        RewriteEngine On
        RewriteRule ^favicon\.ico$ skins/elastic/images/favicon.ico
    </IfModule>

    # Mejorar el manejo de archivos estáticos
    <FilesMatch "\.(ico|gif|jpe?g|png|css|js|svg|woff|woff2|ttf|eot)$">
        Header set Cache-Control "max-age=2592000, public"
    </FilesMatch>
</Directory>

# Acceso específico a directorios de recursos estáticos
<Directory /var/lib/roundcube/program/js>
    Require all granted
</Directory>

<Directory /var/lib/roundcube/program/skins>
    Require all granted
</Directory>
EOF

# 4. Habilitar módulos necesarios de Apache
print_message "Habilitando módulos de Apache necesarios..."
a2enmod headers
a2enmod rewrite
a2enmod expires

# 5. Habilitar la configuración de Roundcube
print_message "Habilitando configuración de Roundcube..."
a2enconf roundcube

# 6. Limpiar la caché de Roundcube
print_message "Limpiando caché de Roundcube..."
rm -rf /var/lib/roundcube/temp/*

# 7. Reiniciar Apache
print_message "Reiniciando Apache..."
systemctl restart apache2

print_message "Corrigiendo errores 403 en Roundcube..."

# 1. Corregir estructura de directorios y enlaces simbólicos
print_message "Reconstruyendo estructura de directorios..."
mkdir -p /var/lib/roundcube/program
mkdir -p /var/lib/roundcube/skins
mkdir -p /var/lib/roundcube/plugins

# 2. Eliminar enlaces simbólicos existentes si los hay
rm -f /var/lib/roundcube/program/js
rm -f /var/lib/roundcube/program/skins
rm -f /var/lib/roundcube/plugins

# 3. Crear nuevos enlaces simbólicos
print_message "Creando enlaces simbólicos correctos..."
ln -sf /usr/share/roundcube/program/js /var/lib/roundcube/program/
ln -sf /usr/share/roundcube/program/skins /var/lib/roundcube/
ln -sf /usr/share/roundcube/plugins /var/lib/roundcube/

# 4. Corregir permisos de forma recursiva
print_message "Aplicando permisos correctos..."
find /usr/share/roundcube -type d -exec chmod 755 {} \;
find /usr/share/roundcube -type f -exec chmod 644 {} \;
find /var/lib/roundcube -type d -exec chmod 755 {} \;
find /var/lib/roundcube -type f -exec chmod 644 {} \;

# 5. Establecer propietario correcto
print_message "Estableciendo propietario correcto..."
chown -R www-data:www-data /usr/share/roundcube
chown -R www-data:www-data /var/lib/roundcube
chown -R www-data:www-data /etc/roundcube

# 6. Configuración de Apache actualizada
print_message "Actualizando configuración de Apache..."
cat > /etc/apache2/conf-available/roundcube.conf << EOF
Alias /webmail /var/lib/roundcube

<Directory /var/lib/roundcube>
    Options +FollowSymLinks
    DirectoryIndex index.php
    
    <IfModule mod_authz_core.c>
        Require all granted
    </IfModule>
    
    <IfModule !mod_authz_core.c>
        Order Allow,Deny
        Allow from all
    </IfModule>
</Directory>

<Directory /usr/share/roundcube>
    Options +FollowSymLinks
    Require all granted
</Directory>

<Directory /var/lib/roundcube/program>
    Options +FollowSymLinks
    Require all granted
</Directory>

<Directory /var/lib/roundcube/skins>
    Options +FollowSymLinks
    Require all granted
</Directory>

<Directory /var/lib/roundcube/plugins>
    Options +FollowSymLinks
    Require all granted
</Directory>
EOF

# 7. Configurar SELinux si está presente
if command -v semanage &> /dev/null; then
    print_message "Configurando SELinux..."
    semanage fcontext -a -t httpd_sys_content_t "/var/lib/roundcube(/.*)?"
    semanage fcontext -a -t httpd_sys_content_t "/usr/share/roundcube(/.*)?"
    restorecon -Rv /var/lib/roundcube
    restorecon -Rv /usr/share/roundcube
fi

# 8. Verificar y habilitar módulos de Apache necesarios
print_message "Verificando módulos de Apache..."
a2enmod headers
a2enmod rewrite
a2enmod expires
a2enmod alias

# 9. Aplicar configuración de Roundcube
print_message "Aplicando configuración..."
a2enconf roundcube

# 10. Limpiar caché
print_message "Limpiando caché..."
rm -rf /var/lib/roundcube/temp/*
mkdir -p /var/lib/roundcube/temp
chown www-data:www-data /var/lib/roundcube/temp

# 11. Reiniciar Apache
print_message "Reiniciando Apache..."
systemctl restart apache2

print_message "Corrigiendo dependencias específicas de Roundcube..."

# 1. Crear estructura completa de directorios
print_message "Creando estructura de directorios..."
mkdir -p /var/lib/roundcube/skins/elastic/deps
mkdir -p /var/lib/roundcube/program/js
mkdir -p /var/lib/roundcube/plugins/jqueryui/js/i18n

# 2. Copiar archivos específicos que faltan
print_message "Copiando archivos específicos..."

# Bootstrap y dependencias
cp -f /usr/share/roundcube/skins/elastic/deps/bootstrap.min.css /var/lib/roundcube/skins/elastic/deps/
cp -f /usr/share/roundcube/skins/elastic/deps/bootstrap.bundle.min.js /var/lib/roundcube/skins/elastic/deps/

# jQuery y otros JS
cp -f /usr/share/roundcube/program/js/jquery.min.js /var/lib/roundcube/program/js/
cp -f /usr/share/roundcube/program/js/jstz.min.js /var/lib/roundcube/program/js/

# jQuery UI y sus dependencias
cp -f /usr/share/roundcube/plugins/jqueryui/js/jquery-ui.min.js /var/lib/roundcube/plugins/jqueryui/js/
cp -f /usr/share/roundcube/plugins/jqueryui/js/i18n/datepicker-es.min.js /var/lib/roundcube/plugins/jqueryui/js/i18n/

# 3. Configurar permisos específicos
print_message "Configurando permisos..."
find /var/lib/roundcube/skins/elastic/deps -type f -exec chmod 644 {} \;
find /var/lib/roundcube/program/js -type f -exec chmod 644 {} \;
find /var/lib/roundcube/plugins/jqueryui -type f -exec chmod 644 {} \;

# 4. Establecer propietario correcto
print_message "Estableciendo propietario..."
chown -R www-data:www-data /var/lib/roundcube/skins/elastic/deps
chown -R www-data:www-data /var/lib/roundcube/program/js
chown -R www-data:www-data /var/lib/roundcube/plugins

# 5. Actualizar configuración de Apache específica para estas rutas
print_message "Actualizando configuración de Apache..."
cat > /etc/apache2/conf-available/roundcube-deps.conf << EOF
<Directory /var/lib/roundcube/skins/elastic/deps>
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<Directory /var/lib/roundcube/program/js>
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<Directory /var/lib/roundcube/plugins/jqueryui>
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<FilesMatch "\.(css|js)$">
    Header set Cache-Control "max-age=7200, public"
</FilesMatch>
EOF

# 6. Habilitar la nueva configuración
print_message "Habilitando nueva configuración..."
a2enconf roundcube-deps

# 7. Verificar y corregir enlaces simbólicos si es necesario
print_message "Verificando enlaces simbólicos..."
for dir in deps js jqueryui; do
    if [ -L "/var/lib/roundcube/$dir" ]; then
        rm "/var/lib/roundcube/$dir"
        cp -r "/usr/share/roundcube/$dir" "/var/lib/roundcube/"
    fi
done

# 8. Limpiar caché
print_message "Limpiando caché..."
rm -rf /var/lib/roundcube/temp/*
mkdir -p /var/lib/roundcube/temp
chown www-data:www-data /var/lib/roundcube/temp

# 9. Reiniciar Apache
print_message "Reiniciando Apache..."
systemctl restart apache2

# 10. Verificar que los archivos existen y tienen los permisos correctos
print_message "Verificando archivos..."
FILES_TO_CHECK=(
    "/var/lib/roundcube/skins/elastic/deps/bootstrap.min.css"
    "/var/lib/roundcube/skins/elastic/deps/bootstrap.bundle.min.js"
    "/var/lib/roundcube/program/js/jquery.min.js"
    "/var/lib/roundcube/program/js/jstz.min.js"
    "/var/lib/roundcube/plugins/jqueryui/js/jquery-ui.min.js"
    "/var/lib/roundcube/plugins/jqueryui/js/i18n/datepicker-es.min.js"
)

for file in "${FILES_TO_CHECK[@]}"; do
    if [ -f "$file" ]; then
        print_message "✓ $file existe y es accesible"
    else
        print_error "✗ $file no existe o no es accesible"
    fi
done

print_message "Corrigiendo acceso a imágenes de Roundcube..."

# Rouncube recursos staticos
# 1. Crear estructura de directorios para imágenes
print_message "Creando estructura de directorios para imágenes..."
mkdir -p /var/lib/roundcube/skins/elastic/images

# 2. Copiar favicon y otras imágenes
print_message "Copiando imágenes..."
cp -rf /usr/share/roundcube/skins/elastic/images/* /var/lib/roundcube/skins/elastic/images/

# 3. Establecer permisos correctos
print_message "Estableciendo permisos..."
find /var/lib/roundcube/skins/elastic/images -type d -exec chmod 755 {} \;
find /var/lib/roundcube/skins/elastic/images -type f -exec chmod 644 {} \;

# 4. Establecer propietario correcto
print_message "Estableciendo propietario..."
chown -R www-data:www-data /var/lib/roundcube/skins/elastic/images

# 5. Actualizar configuración de Apache para imágenes
print_message "Actualizando configuración de Apache..."
cat > /etc/apache2/conf-available/roundcube-images.conf << EOF
<Directory /var/lib/roundcube/skins/elastic/images>
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

# Configuración específica para tipos de archivos de imagen
<FilesMatch "\.(ico|png|jpg|jpeg|gif|svg)$">
    Header set Cache-Control "max-age=7200, public"
</FilesMatch>

# Regla específica para favicon
<Location /webmail/skins/elastic/images/favicon.ico>
    Require all granted
</Location>
EOF

# 6. Habilitar la nueva configuración
print_message "Habilitando nueva configuración..."
a2enconf roundcube-images

# 7. Verificar que el favicon existe
print_message "Verificando favicon..."
if [ -f "/var/lib/roundcube/skins/elastic/images/favicon.ico" ]; then
    print_message "✓ Favicon encontrado"
else
    print_error "✗ Favicon no encontrado - copiando de nuevo"
    cp /usr/share/roundcube/skins/elastic/images/favicon.ico /var/lib/roundcube/skins/elastic/images/
fi

# 8. Asegurar que los módulos necesarios están habilitados
print_message "Verificando módulos de Apache..."
a2enmod headers
a2enmod mime

# 9. Agregar tipos MIME específicos si no existen
print_message "Configurando tipos MIME..."
if ! grep -q "image/x-icon" /etc/mime.types; then
    echo "image/x-icon ico" >> /etc/mime.types
fi

# 10. Reiniciar Apache
print_message "Reiniciando Apache..."
systemctl restart apache2

# 11. Verificación final
print_message "Verificando permisos del favicon..."
ls -l /var/lib/roundcube/skins/elastic/images/favicon.ico

# Mensaje final actualizado
print_message "Instalación completada!"
print_message "Accesos:"
print_message "- Webmail principal: http://$DOMAIN/webmail"
print_message "- Webmail (subdominio): http://mail.$DOMAIN"
print_message "- PostfixAdmin principal: http://$DOMAIN/postfixadmin"
print_message "- PostfixAdmin (subdominio): http://admin.$DOMAIN"
print_message "- Contraseña de configuración inicial de PostfixAdmin: admin123"
print_message ""
print_message "Para completar la configuración de PostfixAdmin:"
print_message "1. Accede a http://admin.$DOMAIN/setup.php"
print_message "2. Usa la contraseña de configuración: admin123"
print_message "3. Crea tu cuenta de superadministrador"
print_message "4. ¡Listo para gestionar tus dominios y usuarios de correo!"
print_message ""
print_message "IMPORTANTE: No olvides configurar los registros DNS:"
print_message "mail.$DOMAIN.    IN A    $SERVER_IP"
print_message "admin.$DOMAIN.   IN A    $SERVER_IP"
print_message "MX $DOMAIN.      IN MX   10 mail.$DOMAIN."
print_message ""
print_message "También recomendamos configurar registros SPF y DKIM después de la instalación"
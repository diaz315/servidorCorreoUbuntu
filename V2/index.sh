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
mysql -e "CREATE DATABASE IF NOT EXISTS mailserver;"
mysql -e "CREATE DATABASE IF NOT EXISTS postfixadmin;"

# Crear usuarios con mysql_native_password
mysql -e "CREATE USER IF NOT EXISTS 'postfix'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_POSTFIX_PASS';"
mysql -e "CREATE USER IF NOT EXISTS 'postfixadmin'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_POSTFIX_PASS';"
mysql -e "CREATE USER IF NOT EXISTS 'mailadmin'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ADMIN_PASS';"

# Asignar permisos
mysql -e "GRANT SELECT ON mailserver.* TO 'postfix'@'localhost';"
mysql -e "GRANT ALL PRIVILEGES ON postfixadmin.* TO 'postfixadmin'@'localhost';"
mysql -e "GRANT ALL PRIVILEGES ON mailserver.* TO 'mailadmin'@'localhost';"

# Asegurar el método de autenticación con ALTER USER
mysql -e "ALTER USER 'postfix'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_POSTFIX_PASS';"
mysql -e "ALTER USER 'postfixadmin'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_POSTFIX_PASS';"
mysql -e "ALTER USER 'mailadmin'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ADMIN_PASS';"

mysql -e "FLUSH PRIVILEGES;"

# Crear tablas
mysql mailserver << EOF
CREATE TABLE \`virtual_domains\` (
    \`id\` int(11) NOT NULL auto_increment,
    \`name\` varchar(50) NOT NULL,
    PRIMARY KEY (\`id\`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE \`virtual_users\` (
    \`id\` int(11) NOT NULL auto_increment,
    \`domain_id\` int(11) NOT NULL,
    \`email\` varchar(100) NOT NULL,
    \`password\` varchar(255) NOT NULL,
    PRIMARY KEY (\`id\`),
    UNIQUE KEY \`email\` (\`email\`),
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO virtual_domains (id, name) VALUES ('1', '$DOMAIN');
EOF

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
hosts = 127.0.0.1
user = postfix
password = $MYSQL_POSTFIX_PASS
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s'
EOF

cat > /etc/postfix/mysql-virtual-mailbox-maps.cf << EOF
hosts = 127.0.0.1
user = postfix
password = $MYSQL_POSTFIX_PASS
dbname = mailserver
query = SELECT 1 FROM virtual_users WHERE email='%s'
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
connect = host=127.0.0.1 dbname=mailserver user=postfix password=$MYSQL_POSTFIX_PASS
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email as user, password FROM virtual_users WHERE email='%u'
EOF

# 5. Configuración de Roundcube
print_message "Configurando Roundcube..."

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
mkdir -p /var/mail/vhosts/$DOMAIN
chown -R vmail:vmail /var/mail
chmod -R 700 /var/mail

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
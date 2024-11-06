#!/bin/bash

# Variables
SERVER_IP="137.184.59.37"
DOMAIN="jdtech.com.co"
HOSTNAME="mail.$DOMAIN"
# Generación de contraseñas seguras automáticas
MYSQL_ROOT_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
MYSQL_POSTFIX_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
MYSQL_ADMIN_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
DES_KEY=$(openssl rand -base64 18)
POSTFIXADMIN_SETUP_PASSWORD="admin123"
POSTFIXADMIN_SETUP_PASSWORD_HASH=$(echo -n "$POSTFIXADMIN_SETUP_PASSWORD" | openssl whirlpool -binary | base64)

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

# Guardar credenciales en un archivo seguro
save_credentials() {
    cat > /root/mail_credentials.txt << EOF
Credenciales del Servidor de Correo
==================================
MySQL Root Password: $MYSQL_ROOT_PASS
MySQL Postfix User Password: $MYSQL_POSTFIX_PASS
MySQL Admin Password: $MYSQL_ADMIN_PASS
PostfixAdmin Setup Password: $POSTFIXADMIN_SETUP_PASSWORD
Hostname: $HOSTNAME
Domain: $DOMAIN
EOF
    chmod 600 /root/mail_credentials.txt
    print_message "Credenciales guardadas en /root/mail_credentials.txt"
}

# Preparación inicial del sistema
print_message "Actualizando el sistema..."
DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y

# Instalación de paquetes necesarios
print_message "Instalando paquetes necesarios..."
DEBIAN_FRONTEND=noninteractive apt install -y \
    postfix postfix-mysql dovecot-core dovecot-imapd dovecot-pop3d \
    dovecot-lmtpd dovecot-mysql mysql-server swaks \
    roundcube roundcube-mysql roundcube-core \
    php-zip php-imagick php-mysql php-xml php-mbstring php-curl roundcube-plugins \
    postfixadmin php-imap apache2 \
    net-tools

# Preconfigurar Postfix para instalación no interactiva
print_message "Preconfigurando Postfix..."
debconf-set-selections <<< "postfix postfix/mailname string $HOSTNAME"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
debconf-set-selections <<< "postfix postfix/destinations string $HOSTNAME, $DOMAIN, localhost.localdomain, localhost"

# Configurar hostname
print_message "Configurando hostname..."
hostnamectl set-hostname $HOSTNAME
echo "$SERVER_IP $HOSTNAME mail" >> /etc/hosts

# Guardar credenciales
save_credentials

# Configuración inicial de MySQL
print_message "Configurando MySQL..."
systemctl start mysql

# Asegurar MySQL y crear bases de datos
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH 'mysql_native_password' BY '$MYSQL_ROOT_PASS';"
mysql -uroot -p"$MYSQL_ROOT_PASS" << EOF
CREATE DATABASE IF NOT EXISTS mailserver CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE DATABASE IF NOT EXISTS postfixadmin CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS 'postfix'@'127.0.0.1' IDENTIFIED BY '$MYSQL_POSTFIX_PASS';
GRANT SELECT ON mailserver.* TO 'postfix'@'127.0.0.1';
CREATE USER IF NOT EXISTS 'postfixadmin'@'localhost' IDENTIFIED BY '$MYSQL_POSTFIX_PASS';
GRANT ALL PRIVILEGES ON postfixadmin.* TO 'postfixadmin'@'localhost';
CREATE USER IF NOT EXISTS 'mailadmin'@'localhost' IDENTIFIED BY '$MYSQL_ADMIN_PASS';
GRANT ALL PRIVILEGES ON mailserver.* TO 'mailadmin'@'localhost';
FLUSH PRIVILEGES;
EOF

print_message "Configuración inicial completada exitosamente."
print_message "Puedes encontrar las credenciales en /root/mail_credentials.txt"

#!/bin/bash

# Asumiendo que las variables y funciones de la Parte 1 están definidas

print_message "Configurando PostfixAdmin..."

# Crear tablas básicas en mailserver
mysql -uroot -p"$MYSQL_ROOT_PASS" mailserver << EOF
CREATE TABLE IF NOT EXISTS \`virtual_domains\` (
    \`id\` int(11) NOT NULL auto_increment,
    \`name\` varchar(50) NOT NULL,
    PRIMARY KEY (\`id\`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS \`virtual_users\` (
    \`id\` int(11) NOT NULL auto_increment,
    \`domain_id\` int(11) NOT NULL,
    \`email\` varchar(100) NOT NULL,
    \`password\` varchar(255) NOT NULL,
    PRIMARY KEY (\`id\`),
    UNIQUE KEY \`email\` (\`email\`),
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO virtual_domains (id, name) VALUES ('1', '$DOMAIN') ON DUPLICATE KEY UPDATE name='$DOMAIN';
EOF

# Crear y configurar directorios necesarios para PostfixAdmin
print_message "Configurando directorios de PostfixAdmin..."
mkdir -p /var/lib/postfixadmin/templates_c
mkdir -p /var/log/postfixadmin
touch /var/log/postfixadmin/error.log
touch /var/log/postfixadmin.log

# Establecer permisos correctos
chown -R www-data:www-data /var/lib/postfixadmin
chown -R www-data:www-data /var/log/postfixadmin
chown www-data:www-data /var/log/postfixadmin.log
chmod -R 755 /var/lib/postfixadmin
chmod 640 /var/log/postfixadmin.log

# Configuración mejorada de PostfixAdmin
print_message "Creando configuración de PostfixAdmin..."
cat > /etc/postfixadmin/config.local.php << EOF
<?php
\$CONF['database_type'] = 'mysqli';
\$CONF['database_host'] = 'localhost';
\$CONF['database_user'] = 'postfixadmin';
\$CONF['database_password'] = '$MYSQL_POSTFIX_PASS';
\$CONF['database_name'] = 'postfixadmin';
\$CONF['configured'] = true;
\$CONF['setup_password'] = '$POSTFIXADMIN_SETUP_PASSWORD_HASH';
\$CONF['default_language'] = 'es';
\$CONF['domain_path'] = '/var/mail/vhosts/%d';
\$CONF['domain_in_mailbox'] = 'YES';
\$CONF['fetchmail'] = 'NO';
\$CONF['show_footer_text'] = 'NO';
\$CONF['quota'] = 'YES';
\$CONF['domain_quota'] = 'YES';
\$CONF['database_prefix'] = '';
\$CONF['used_quotas'] = 'YES';
\$CONF['new_quota_table'] = 'YES';
\$CONF['smtp_server'] = 'localhost';
\$CONF['smtp_port'] = '25';
\$CONF['encrypt'] = 'dovecot:SHA512-CRYPT';
\$CONF['dovecotpw'] = "/usr/bin/doveadm pw";
\$CONF['min_password_length'] = 8;
\$CONF['generate_password'] = 'NO';
\$CONF['password_validation'] = array(
    '/.*/',              // Cualquier caracter
    '/[A-Z]/',          // Al menos una mayúscula
    '/[a-z]/',          // Al menos una minúscula
    '/[0-9]/',          // Al menos un número
    '/.{8,}/'           // Mínimo 8 caracteres
);
// Logging mejorado
\$CONF['logging'] = 'YES';
\$CONF['log_level'] = 'ERROR';
\$CONF['logfile'] = '/var/log/postfixadmin.log';
// Configuraciones adicionales de seguridad
\$CONF['smtp_client'] = 'YES';
\$CONF['emailcheck_resolve_domain'] = 'YES';
\$CONF['create_mailbox_subdirs_prefix'] = 'INBOX.';
\$CONF['page_size'] = '10';
\$CONF['default_aliases'] = array (
    'abuse' => 'abuse@$DOMAIN',
    'hostmaster' => 'hostmaster@$DOMAIN',
    'postmaster' => 'postmaster@$DOMAIN',
    'webmaster' => 'webmaster@$DOMAIN'
);
// Configuraciones de límites
\$CONF['domain_quota_default'] = '10240';  // 10GB por dominio
\$CONF['maxquota'] = '10240';             // 10GB máximo por buzón
\$CONF['aliases'] = '10';                 // Máximo de alias por dominio
\$CONF['mailboxes'] = '10';               // Máximo de buzones por dominio
\$CONF['maxquota_size'] = '10240';
EOF

# Establecer permisos correctos para config.local.php
chown www-data:www-data /etc/postfixadmin/config.local.php
chmod 640 /etc/postfixadmin/config.local.php

# Configurar Apache Virtual Hosts
print_message "Configurando Virtual Hosts de Apache..."
cat > /etc/apache2/sites-available/postfixadmin.conf << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    ServerName admin.$DOMAIN
    DocumentRoot /usr/share/postfixadmin/public

    <Directory /usr/share/postfixadmin/public>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        
        <IfModule mod_php.c>
            php_flag register_globals off
            php_flag magic_quotes_gpc off
            php_flag magic_quotes_runtime off
            php_flag short_open_tag on
            php_flag register_argc_argv off
            php_flag allow_url_fopen off
        </IfModule>
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/postfixadmin_error.log
    CustomLog \${APACHE_LOG_DIR}/postfixadmin_access.log combined
</VirtualHost>
EOF

# Habilitar el sitio y los módulos necesarios
a2ensite postfixadmin
a2enmod rewrite
a2enmod ssl

# Reiniciar servicios
print_message "Reiniciando servicios..."
systemctl restart apache2
systemctl restart mysql

# Crear usuario virtual mail
print_message "Configurando usuario virtual mail..."
groupadd -g 5000 vmail 2>/dev/null || true
useradd -g vmail -u 5000 vmail -d /var/mail -m 2>/dev/null || true
mkdir -p /var/mail/vhosts/$DOMAIN
chown -R vmail:vmail /var/mail
chmod -R 700 /var/mail

print_message "Configuración de PostfixAdmin completada."
print_message "Por favor, accede a http://admin.$DOMAIN/setup.php"
print_message "Usa la contraseña de configuración: $POSTFIXADMIN_SETUP_PASSWORD"

#!/bin/bash

# Asumiendo que las variables y funciones de las Partes 1 y 2 están definidas

print_message "Configurando Postfix..."

# Crear directorios necesarios para SSL
mkdir -p /etc/postfix/ssl
mkdir -p /etc/postfix/mysql

# Generar certificado SSL autofirmado
print_message "Generando certificado SSL..."
openssl req -new -x509 -days 365 -nodes \
    -out /etc/postfix/ssl/smtp.crt \
    -keyout /etc/postfix/ssl/smtp.key \
    -subj "/C=CO/ST=State/L=City/O=Organization/CN=$DOMAIN"

# Establecer permisos correctos para certificados
chmod 600 /etc/postfix/ssl/*
chown postfix:postfix /etc/postfix/ssl/*

# Configuración principal de Postfix
print_message "Creando configuración principal de Postfix..."
cat > /etc/postfix/main.cf << EOF
# Configuración básica
smtpd_banner = \$myhostname ESMTP \$mail_name
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 3.6

# Configuración de hostname y dominio
myhostname = $HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain
mydestination = localhost
relayhost =

# Configuración de red
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
inet_interfaces = all
inet_protocols = all

# Configuración de dominios y buzones virtuales
virtual_mailbox_domains = mysql:/etc/postfix/mysql/virtual-mailbox-domains.cf
virtual_mailbox_maps = mysql:/etc/postfix/mysql/virtual-mailbox-maps.cf
virtual_alias_maps = mysql:/etc/postfix/mysql/virtual-alias-maps.cf
virtual_transport = lmtp:unix:private/dovecot-lmtp

# Configuración de directorios virtuales
virtual_mailbox_base = /var/mail/vhosts
virtual_minimum_uid = 5000
virtual_uid_maps = static:5000
virtual_gid_maps = static:5000

# Límites y delimitadores
mailbox_size_limit = 0
message_size_limit = 52428800
recipient_delimiter = +

# Autenticación SASL
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = \$myhostname
broken_sasl_auth_clients = yes

# Configuración TLS
smtpd_tls_cert_file = /etc/postfix/ssl/smtp.crt
smtpd_tls_key_file = /etc/postfix/ssl/smtp.key
smtpd_tls_security_level = may
smtpd_tls_auth_only = yes
smtp_tls_security_level = may
smtp_tls_loglevel = 1
smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3
smtp_tls_mandatory_protocols = !SSLv2, !SSLv3
smtpd_tls_protocols = !SSLv2, !SSLv3
smtp_tls_protocols = !SSLv2, !SSLv3

# Restricciones SMTP
smtpd_recipient_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_unauth_destination,
    reject_invalid_hostname,
    reject_non_fqdn_hostname,
    reject_non_fqdn_sender,
    reject_non_fqdn_recipient,
    reject_unknown_sender_domain,
    reject_unknown_recipient_domain,
    reject_rbl_client zen.spamhaus.org

smtpd_relay_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_unauth_destination

# Configuraciones de seguridad adicionales
smtpd_helo_required = yes
disable_vrfy_command = yes
smtpd_delay_reject = yes
smtpd_helo_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_invalid_helo_hostname,
    reject_non_fqdn_helo_hostname

smtpd_sender_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_non_fqdn_sender,
    reject_unknown_sender_domain

# Ajustes de rendimiento
default_process_limit = 100
smtp_destination_concurrency_limit = 2
smtp_destination_rate_delay = 1s
local_destination_concurrency_limit = 2
default_destination_concurrency_limit = 5

# Configuraciones de cola
maximal_queue_lifetime = 5d
bounce_queue_lifetime = 5d
queue_run_delay = 300s
minimal_backoff_time = 300s
maximal_backoff_time = 4000s
queue_minfree = 120000000

# Logging
debug_peer_level = 2
debugger_command =
    PATH=/bin:/usr/bin:/usr/local/bin:/usr/X11R6/bin
    ddd \$daemon_directory/\$process_name \$process_id & sleep 5
EOF

# Configuración de archivos MySQL para Postfix
print_message "Configurando archivos MySQL para Postfix..."

# Virtual Domains
cat > /etc/postfix/mysql/virtual-mailbox-domains.cf << EOF
hosts = 127.0.0.1
user = postfix
password = $MYSQL_POSTFIX_PASS
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s'
EOF

# Virtual Mailboxes
cat > /etc/postfix/mysql/virtual-mailbox-maps.cf << EOF
hosts = 127.0.0.1
user = postfix
password = $MYSQL_POSTFIX_PASS
dbname = mailserver
query = SELECT 1 FROM virtual_users WHERE email='%s'
EOF

# Virtual Aliases
cat > /etc/postfix/mysql/virtual-alias-maps.cf << EOF
hosts = 127.0.0.1
user = postfix
password = $MYSQL_POSTFIX_PASS
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s'
EOF

# Establecer permisos correctos
chmod 0640 /etc/postfix/mysql/*
chown root:postfix /etc/postfix/mysql/*

# Configurar master.cf
print_message "Configurando master.cf..."
cat > /etc/postfix/master.cf << EOF
# Servicios SMTP
smtp      inet  n       -       y       -       -       smtpd
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

# Servicios adicionales
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
EOF

print_message "Reiniciando Postfix..."
systemctl restart postfix

print_message "Configuración de Postfix completada."
print_message "Verificando estado del servicio..."
postfix_status=$(systemctl is-active postfix)
if [ "$postfix_status" = "active" ]; then
    print_message "Postfix está funcionando correctamente"
else
    print_error "Postfix no está funcionando. Revisa los logs en /var/log/mail.log"
fi

#!/bin/bash

# Asumiendo que las variables y funciones de las partes anteriores están definidas

print_message "Configurando Dovecot..."

# Crear directorios necesarios
mkdir -p /etc/dovecot/conf.d
mkdir -p /var/mail/vhosts
mkdir -p /var/mail/attachments

# Configuración principal de Dovecot
print_message "Creando configuración principal de Dovecot..."
cat > /etc/dovecot/dovecot.conf << EOF
# Protocolos habilitados
protocols = imap pop3 lmtp
listen = *

# Ubicación de buzones
mail_location = maildir:/var/mail/vhosts/%d/%n
mail_privileged_group = mail
mail_attachment_dir = /var/mail/attachments
mail_attachment_min_size = 128k

# Configuración de usuario virtual
first_valid_uid = 5000
first_valid_gid = 5000

# Límites y seguridad
default_process_limit = 100
default_client_limit = 1000
default_vsz_limit = 256M

# SSL
ssl = required
ssl_cert = </etc/postfix/ssl/smtp.crt
ssl_key = </etc/postfix/ssl/smtp.key
ssl_min_protocol = TLSv1.2
ssl_cipher_list = EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH
ssl_prefer_server_ciphers = yes

# Configuración de namespace
namespace inbox {
    type = private
    separator = /
    prefix =
    inbox = yes
    
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
    mailbox Archive {
        auto = subscribe
        special_use = \Archive
    }
}

# Configuración del servicio LMTP
service lmtp {
    unix_listener /var/spool/postfix/private/dovecot-lmtp {
        mode = 0600
        user = postfix
        group = postfix
    }
}

# Configuración del servicio auth
service auth {
    unix_listener /var/spool/postfix/private/auth {
        mode = 0666
        user = postfix
        group = postfix
    }
    
    unix_listener auth-userdb {
        mode = 0600
        user = vmail
        group = vmail
    }
}

# Configuración del servicio auth-worker
service auth-worker {
    user = vmail
}

# Configuración de autenticación
auth_mechanisms = plain login
passdb {
    driver = sql
    args = /etc/dovecot/dovecot-sql.conf.ext
}

userdb {
    driver = static
    args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
}

# Configuración de logs
log_path = /var/log/dovecot.log
info_log_path = /var/log/dovecot-info.log
debug_log_path = /var/log/dovecot-debug.log
mail_debug = no
auth_debug = no
verbose_ssl = no

# Configuración de cuotas
mail_plugins = $mail_plugins quota
protocol imap {
    mail_plugins = $mail_plugins imap_quota
    imap_idle_notify_interval = 29 mins
}

plugin {
    quota = maildir:User quota
    quota_rule = *:storage=5G
    quota_rule2 = Trash:storage=1G
    quota_warning = storage=95%% quota-warning 95 %u
    quota_warning2 = storage=80%% quota-warning 80 %u
}

# Configuración de caché
protocol !indexer-worker {
   mail_vsize_bg_after_count = 100
}
EOF

# Configuración de SQL para Dovecot
print_message "Configurando SQL para Dovecot..."
cat > /etc/dovecot/dovecot-sql.conf.ext << EOF
driver = mysql
connect = host=127.0.0.1 dbname=mailserver user=postfix password=$MYSQL_POSTFIX_PASS
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email as user, password FROM virtual_users WHERE email='%u'
user_query = SELECT concat('/var/mail/vhosts/', substring_index(email, '@', -1), '/', substring_index(email, '@', 1)) AS home, 5000 AS uid, 5000 AS gid, concat('*:bytes=', quota) AS quota_rule FROM virtual_users WHERE email='%u'
iterate_query = SELECT email AS user FROM virtual_users
EOF

# Crear archivo de configuración para cuotas
print_message "Configurando script de advertencia de cuotas..."
cat > /usr/local/bin/quota-warning.sh << 'EOF'
#!/bin/sh
PERCENT=$1
USER=$2
cat << EOF | /usr/lib/dovecot/dovecot-lda -d $USER -o "plugin/quota=maildir:User quota:noenforcing"
From: postmaster@$DOMAIN
Subject: Advertencia de cuota de buzón - $PERCENT% alcanzado

Su buzón de correo ha alcanzado el $PERCENT% de su cuota asignada.
Por favor, libere espacio eliminando correos innecesarios.

Saludos,
Administrador del Sistema
EOF
EOF

# Establecer permisos correctos
chmod +x /usr/local/bin/quota-warning.sh
chown -R vmail:vmail /var/mail/vhosts
chown -R vmail:dovecot /etc/dovecot
chmod -R 770 /var/mail/vhosts
chmod -R 600 /etc/dovecot/*.conf*
chmod -R 750 /etc/dovecot
chmod -R 770 /var/mail/attachments
chown -R vmail:vmail /var/mail/attachments

# Crear directorios de logs
touch /var/log/dovecot.log
touch /var/log/dovecot-info.log
touch /var/log/dovecot-debug.log
chown vmail:adm /var/log/dovecot*
chmod 640 /var/log/dovecot*

# Reiniciar Dovecot
print_message "Reiniciando Dovecot..."
systemctl restart dovecot

# Verificar estado
print_message "Verificando estado de Dovecot..."
dovecot_status=$(systemctl is-active dovecot)
if [ "$dovecot_status" = "active" ]; then
    print_message "Dovecot está funcionando correctamente"
    print_message "Verificando puertos..."
    netstat -tlpn | grep dovecot
else
    print_error "Dovecot no está funcionando. Revisa los logs en /var/log/dovecot.log"
fi

#!/bin/bash

# Asumiendo que las variables y funciones de las partes anteriores están definidas

print_message "Configurando Roundcube..."

# Preconfigurar Roundcube para instalación no interactiva
debconf-set-selections <<< "roundcube-core roundcube/dbconfig-install boolean true"
debconf-set-selections <<< "roundcube-core roundcube/database-type select mysql"
debconf-set-selections <<< "roundcube-core roundcube/mysql/admin-pass password $MYSQL_ROOT_PASS"
debconf-set-selections <<< "roundcube-core roundcube/db/dbname string roundcube"
debconf-set-selections <<< "roundcube-core roundcube/db/user string roundcube"

# Crear base de datos y usuario para Roundcube
print_message "Configurando base de datos para Roundcube..."
ROUNDCUBE_DB_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

mysql -uroot -p"$MYSQL_ROOT_PASS" << EOF
CREATE DATABASE IF NOT EXISTS roundcube CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'roundcube'@'localhost' IDENTIFIED BY '$ROUNDCUBE_DB_PASS';
GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost';
FLUSH PRIVILEGES;
EOF

# Configuración mejorada de Roundcube
print_message "Creando configuración de Roundcube..."
cat > /etc/roundcube/config.inc.php << EOF
<?php
\$config = array();
\$config['db_dsnw'] = 'mysql://roundcube:${ROUNDCUBE_DB_PASS}@localhost/roundcube';
\$config['default_host'] = 'localhost';
\$config['smtp_server'] = 'localhost';
\$config['smtp_port'] = 587;
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';
\$config['support_url'] = '';
\$config['product_name'] = 'Webmail - $DOMAIN';
\$config['des_key'] = '$DES_KEY';
\$config['plugins'] = array(
    'archive',
    'zipdownload',
    'managesieve',
    'password',
    'newmail_notifier',
    'emoticons',
    'markasjunk'
);
\$config['language'] = 'es_ES';
\$config['spellcheck_engine'] = 'googie';

// Configuraciones de interfaz
\$config['skin'] = 'elastic';
\$config['timezone'] = 'America/Bogota';
\$config['prefer_html'] = true;
\$config['htmleditor'] = true;
\$config['draft_autosave'] = 60;
\$config['preview_pane'] = true;
\$config['layout'] = 'widescreen';
\$config['list_cols'] = array('flag', 'status', 'subject', 'from', 'date', 'size', 'attachment');

// Configuraciones de seguridad
\$config['login_autocomplete'] = 2;
\$config['password_min_length'] = 8;
\$config['password_require_nonalpha'] = true;
\$config['session_lifetime'] = 30;
\$config['session_timeout'] = 10;
\$config['sendmail_delay'] = 0;
\$config['maximum_message_size'] = '50M';
\$config['mime_types'] = '/etc/mime.types';
\$config['ip_check'] = true;

// Configuraciones de caché y rendimiento
\$config['messages_cache'] = 'db';
\$config['messages_cache_threshold'] = 50;
\$config['enable_caching'] = true;
\$config['cache_messages'] = true;
\$config['cache_threads'] = true;
\$config['mem_limit'] = '256M';

// Configuraciones de manejo de adjuntos
\$config['client_upload_max_size'] = '50M';
\$config['upload_progress'] = true;
\$config['image_thumbnail_size'] = 240;
\$config['prefer_plaintext'] = false;
\$config['show_images'] = 0;
\$config['attach_size_limit'] = '50M';

// Configuraciones adicionales de seguridad
\$config['force_https'] = true;
\$config['use_secure_urls'] = true;
\$config['login_rate_limit'] = array(
    'max_attempts' => 3,
    'reset_time' => 300,
    'ban_time' => 900,
);
EOF

# Configurar el virtual host de Apache para Roundcube
print_message "Configurando virtual host para Roundcube..."
cat > /etc/apache2/sites-available/roundcube.conf << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    ServerName mail.$DOMAIN
    DocumentRoot /var/lib/roundcube
    
    ErrorLog \${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog \${APACHE_LOG_DIR}/roundcube_access.log combined
    
    <Directory /var/lib/roundcube/>
        Options -Indexes
        AllowOverride All
        Order allow,deny
        Allow from all
        
        <IfModule mod_php.c>
            AddType application/x-httpd-php .php
            php_flag magic_quotes_gpc Off
            php_flag track_vars On
            php_flag register_globals Off
            php_value include_path .:/usr/share/php
            php_value session.gc_maxlifetime 21600
            php_value session.gc_divisor 500
            php_value session.gc_probability 1
            php_value upload_max_filesize 50M
            php_value post_max_size 50M
            php_value memory_limit 256M
        </IfModule>
    </Directory>
    
    <Directory /var/lib/roundcube/config>
        Order deny,allow
        Deny from all
    </Directory>
    
    <Directory /var/lib/roundcube/temp>
        Order deny,allow
        Deny from all
    </Directory>
    
    <Directory /var/lib/roundcube/logs>
        Order deny,allow
        Deny from all
    </Directory>
</VirtualHost>
EOF

# Habilitar el sitio de Roundcube
a2ensite roundcube

# Establecer permisos correctos
print_message "Estableciendo permisos..."
chown -R www-data:www-data /var/lib/roundcube
chown -R www-data:www-data /etc/roundcube
chmod -R 755 /var/lib/roundcube
chmod -R 755 /etc/roundcube
chmod 640 /etc/roundcube/config.inc.php

# Verificaciones finales
print_message "Realizando verificaciones finales..."

# Función para verificar el estado de un servicio
check_service() {
    local service=$1
    if systemctl is-active --quiet $service; then
        print_message "$service está funcionando correctamente"
        return 0
    else
        print_error "$service no está funcionando"
        return 1
    fi
}

# Verificar servicios
services=("mysql" "postfix" "dovecot" "apache2")
failed_services=0

for service in "${services[@]}"; do
    if ! check_service $service; then
        failed_services=$((failed_services + 1))
    fi
done

# Verificar puertos
print_message "Verificando puertos..."
ports=(25 80 110 143 443 465 587 993 995)
for port in "${ports[@]}"; do
    if netstat -tuln | grep ":$port " > /dev/null; then
        print_message "Puerto $port está abierto"
    else
        print_error "Puerto $port no está abierto"
    fi
done

# Verificar bases de datos
print_message "Verificando bases de datos..."
databases=("mailserver" "postfixadmin" "roundcube")
for db in "${databases[@]}"; do
    if mysql -uroot -p"$MYSQL_ROOT_PASS" -e "use $db" 2>/dev/null; then
        print_message "Base de datos $db existe y es accesible"
    else
        print_error "Base de datos $db no existe o no es accesible"
    fi
done

# Guardar información adicional en el archivo de credenciales
cat >> /root/mail_credentials.txt << EOF

Roundcube Database Password: $ROUNDCUBE_DB_PASS
DES Key: $DES_KEY

Accesos al sistema:
==================
Webmail: https://mail.$DOMAIN
PostfixAdmin: https://admin.$DOMAIN
Roundcube: https://mail.$DOMAIN

Puertos configurados:
====================
25 - SMTP
465 - SMTP sobre SSL
587 - Submission
110 - POP3
995 - POP3 sobre SSL
143 - IMAP
993 - IMAP sobre SSL
EOF

# Mensaje final
if [ $failed_services -eq 0 ]; then
    print_message "¡Instalación completada exitosamente!"
    print_message "Por favor, configure los siguientes registros DNS:"
    echo "
    $HOSTNAME.    IN A    $SERVER_IP
    admin.$DOMAIN.   IN A    $SERVER_IP
    mail.$DOMAIN.    IN A    $SERVER_IP
    
    $DOMAIN.    IN MX   10 mail.$DOMAIN.
    $DOMAIN.    IN TXT  \"v=spf1 mx a ip4:$SERVER_IP ~all\"
    "
else
    print_error "La instalación se completó con $failed_services errores."
    print_error "Por favor, revise los logs del sistema para más detalles."
fi

print_message "Las credenciales y detalles de acceso se han guardado en /root/mail_credentials.txt"
print_message "¡IMPORTANTE! Guarde una copia segura de este archivo y luego considere eliminarlo del servidor."
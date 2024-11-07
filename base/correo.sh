#!/bin/bash

# Variables
SERVER_IP="159.223.102.84"
DOMAIN="jdtech.com.co"
HOSTNAME="mail.$DOMAIN"
MYSQL_POSTFIX_PASS="UnaNuevaContraseña"
MYSQL_ADMIN_PASS="mailpassword"

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

# 1. Preparación del Sistema
print_message "Actualizando el sistema..."
apt update && apt upgrade -y

print_message "Instalando paquetes necesarios..."
apt install -y postfix postfix-mysql dovecot-core dovecot-imapd dovecot-pop3d \
    dovecot-lmtpd dovecot-mysql mysql-server swaks

# Configurar hostname
print_message "Configurando hostname..."
hostnamectl set-hostname $HOSTNAME

# Actualizar /etc/hosts
print_message "Actualizando /etc/hosts..."
echo "$SERVER_IP $HOSTNAME mail" >> /etc/hosts

# 2. Configuración de MySQL
print_message "Configurando MySQL..."
mysql -e "CREATE DATABASE mailserver;"
mysql -e "CREATE USER 'postfix'@'127.0.0.1' IDENTIFIED BY '$MYSQL_POSTFIX_PASS';"
mysql -e "GRANT SELECT ON mailserver.* TO 'postfix'@'127.0.0.1';"
mysql -e "CREATE USER 'mailadmin'@'localhost' IDENTIFIED BY '$MYSQL_ADMIN_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON mailserver.* TO 'mailadmin'@'localhost';"
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

# 3. Configuración de Postfix
print_message "Actualizando configuración de Postfix..."

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

# Debugging
debug_peer_level = 2
debug_peer_list = localhost

# Additional Recommended Settings
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

print_message "Configuración de Postfix actualizada."

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

# 5. Crear usuario virtual mail
print_message "Creando usuario virtual mail..."
groupadd -g 5000 vmail
useradd -g vmail -u 5000 vmail -d /var/mail
mkdir -p /var/mail/vhosts/$DOMAIN
chown -R vmail:vmail /var/mail
chmod -R 700 /var/mail

# 6. Establecer permisos y reiniciar servicios
print_message "Estableciendo permisos..."
chmod 0640 /etc/postfix/mysql-*
chown root:postfix /etc/postfix/mysql-*

print_message "Reiniciando servicios..."
systemctl restart mysql
systemctl restart postfix
systemctl restart dovecot

systemctl enable mysql postfix dovecot

# 7. Verificación final
print_message "Verificando servicios..."
if systemctl is-active --quiet mysql && \
   systemctl is-active --quiet postfix && \
   systemctl is-active --quiet dovecot; then
    print_message "Todos los servicios están funcionando correctamente"
else
    print_error "Algunos servicios no están funcionando correctamente"
    print_message "Por favor, verifica los logs en /var/log/mail.log"
fi

print_message "Instalación completada!"
print_message "Para crear un usuario de prueba, ejecuta:"
print_message "doveadm pw -s SHA512-CRYPT"
print_message "Y luego inserta el usuario en la base de datos con:"
print_message "mysql -u mailadmin -p mailserver"
print_message "INSERT INTO virtual_users (id, domain_id, email, password) VALUES ('1', '1', 'test@$DOMAIN', 'hash_generado');"
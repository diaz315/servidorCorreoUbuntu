#!/bin/bash

# Variables
DOMAIN="jdtech.com.co"
SERVER_IP="159.223.102.84"
MAIL_SUBDOMAIN="mail.$DOMAIN"
ADMIN_SUBDOMAIN="admin.$DOMAIN"
CERT_PATH="/etc/letsencrypt/live/$MAIL_SUBDOMAIN"
SSL_CERT="$CERT_PATH/fullchain.pem"
SSL_KEY="$CERT_PATH/privkey.pem"

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

# Instalar Certbot y el plugin de Apache
print_message "Instalando Certbot y plugin de Apache..."
apt update
apt install -y certbot python3-certbot-apache

# Detener Apache temporalmente
print_message "Deteniendo Apache temporalmente..."
systemctl stop apache2

# Obtener certificados
print_message "Obteniendo certificados SSL para los dominios..."
certbot certonly --standalone \
    -d $MAIL_SUBDOMAIN \
    -d $ADMIN_SUBDOMAIN \
    --agree-tos \
    --non-interactive \
    --email webmaster@$DOMAIN

# Verificar si se obtuvieron los certificados
if [ ! -f "$SSL_CERT" ]; then
    print_error "Error al obtener los certificados SSL"
    systemctl start apache2
    exit 1
fi

# Configurar SSL en Apache solo para los subdominios
print_message "Configurando SSL en Apache..."
cat > /etc/apache2/sites-available/mail-ssl.conf << EOF
<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerAdmin webmaster@$DOMAIN
        ServerName $ADMIN_SUBDOMAIN
        DocumentRoot /usr/share/postfixadmin/public

        SSLEngine on
        SSLCertificateFile $SSL_CERT
        SSLCertificateKeyFile $SSL_KEY

        <Directory /usr/share/postfixadmin/public>
            Options FollowSymLinks MultiViews
            AllowOverride All
            Require all granted
        </Directory>
    </VirtualHost>

    <VirtualHost *:443>
        ServerAdmin webmaster@$DOMAIN
        ServerName $MAIL_SUBDOMAIN
        DocumentRoot /var/lib/roundcube

        SSLEngine on
        SSLCertificateFile $SSL_CERT
        SSLCertificateKeyFile $SSL_KEY

        <Directory /var/lib/roundcube>
            Options FollowSymLinks MultiViews
            AllowOverride All
            Require all granted
        </Directory>
    </VirtualHost>
</IfModule>
EOF

# Configurar SSL en Postfix
print_message "Configurando SSL en Postfix..."
postconf -e "smtpd_tls_cert_file = $SSL_CERT"
postconf -e "smtpd_tls_key_file = $SSL_KEY"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtp_tls_security_level = may"

# Configurar SSL en Dovecot
print_message "Configurando SSL en Dovecot..."
cat > /etc/dovecot/conf.d/10-ssl.conf << EOF
ssl = yes
ssl_cert = <$SSL_CERT
ssl_key = <$SSL_KEY
ssl_min_protocol = TLSv1.2
ssl_prefer_server_ciphers = yes
EOF

# Configurar redirección HTTP a HTTPS solo para los subdominios
print_message "Configurando redirección HTTP a HTTPS..."
cat > /etc/apache2/sites-available/mail.conf << EOF
<VirtualHost *:80>
    ServerName $MAIL_SUBDOMAIN
    ServerAlias $ADMIN_SUBDOMAIN
    Redirect permanent / https://$MAIL_SUBDOMAIN/
</VirtualHost>
EOF

# Habilitar módulos y sitios de Apache
print_message "Habilitando configuración de Apache..."
a2enmod ssl
a2ensite mail-ssl.conf
a2ensite mail.conf

# Configurar renovación automática de certificados
print_message "Configurando renovación automática de certificados..."
echo "0 0 1 * * root certbot renew --quiet --post-hook 'systemctl restart apache2 postfix dovecot'" >> /etc/crontab

# Reiniciar servicios
print_message "Reiniciando servicios..."
systemctl restart apache2
systemctl restart postfix
systemctl restart dovecot

# Verificar estado de los servicios
print_message "Verificando servicios..."
if systemctl is-active --quiet apache2 && \
   systemctl is-active --quiet postfix && \
   systemctl is-active --quiet dovecot; then
    print_message "Todos los servicios están funcionando correctamente"
else
    print_error "Algunos servicios no están funcionando correctamente"
    print_message "Por favor, verifica los logs del sistema"
fi

print_message "¡Configuración SSL completada!"
print_message "Accesos seguros:"
print_message "- Webmail: https://$MAIL_SUBDOMAIN"
print_message "- PostfixAdmin: https://$ADMIN_SUBDOMAIN"
print_message ""
print_message "Los certificados se renovarán automáticamente cada mes"
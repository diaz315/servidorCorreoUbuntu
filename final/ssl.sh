#!/bin/bash

# Variables (asegúrate de que coincidan con tu configuración anterior)
DOMAIN="jdtech.com.co"
SERVER_IP="159.223.102.84"

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
    -d $DOMAIN \
    -d mail.$DOMAIN \
    -d admin.$DOMAIN \
    --agree-tos \
    --non-interactive \
    --email webmaster@$DOMAIN

# Verificar si se obtuvieron los certificados
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    print_error "Error al obtener los certificados SSL"
    systemctl start apache2
    exit 1
fi

# Configurar SSL en Apache
print_message "Configurando SSL en Apache..."
cat > /etc/apache2/sites-available/000-default-ssl.conf << EOF
<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerAdmin webmaster@$DOMAIN
        ServerName $DOMAIN
        DocumentRoot /var/www/html

        SSLEngine on
        SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem

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
    </VirtualHost>

    <VirtualHost *:443>
        ServerAdmin webmaster@$DOMAIN
        ServerName admin.$DOMAIN
        DocumentRoot /usr/share/postfixadmin/public

        SSLEngine on
        SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem

        <Directory /usr/share/postfixadmin/public>
            Options FollowSymLinks MultiViews
            AllowOverride All
            Require all granted
        </Directory>
    </VirtualHost>

    <VirtualHost *:443>
        ServerAdmin webmaster@$DOMAIN
        ServerName mail.$DOMAIN
        DocumentRoot /var/lib/roundcube

        SSLEngine on
        SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem

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
postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$DOMAIN/privkey.pem"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtp_tls_security_level = may"

# Configurar SSL en Dovecot
print_message "Configurando SSL en Dovecot..."
cat > /etc/dovecot/conf.d/10-ssl.conf << EOF
ssl = yes
ssl_cert = </etc/letsencrypt/live/$DOMAIN/fullchain.pem
ssl_key = </etc/letsencrypt/live/$DOMAIN/privkey.pem
ssl_min_protocol = TLSv1.2
ssl_prefer_server_ciphers = yes
EOF

# Configurar redirección HTTP a HTTPS
print_message "Configurando redirección HTTP a HTTPS..."
cat > /etc/apache2/sites-available/000-default.conf << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN mail.$DOMAIN admin.$DOMAIN
    Redirect permanent / https://$DOMAIN/
</VirtualHost>
EOF

# Habilitar módulos y sitios de Apache
print_message "Habilitando configuración de Apache..."
a2enmod ssl
a2ensite default-ssl
a2ensite 000-default-ssl.conf

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
print_message "- Webmail: https://mail.$DOMAIN"
print_message "- PostfixAdmin: https://admin.$DOMAIN"
print_message "- Sitio principal: https://$DOMAIN"
print_message ""
print_message "Los certificados se renovarán automáticamente cada mes"
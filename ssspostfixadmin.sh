#!/bin/bash

# Variables
DOMAIN="jdtech.com.co"
SERVER_IP="159.223.102.84"

# Instalar certbot
apt update
apt install -y certbot python3-certbot-apache

# Obtener certificados SSL
# certbot --apache \
#   -d admin.$DOMAIN \
#   -d mail.$DOMAIN \
#   -d $DOMAIN \
#   --non-interactive \
#   --agree-tos \
#   --email admin@$DOMAIN \
#   --redirect

# Modificar la configuración de Apache para forzar HTTPS
cat > /etc/apache2/sites-available/000-default.conf << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    ServerName $DOMAIN
    Redirect permanent / https://$DOMAIN/
</VirtualHost>

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

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerAdmin webmaster@$DOMAIN
    ServerName admin.$DOMAIN
    DocumentRoot /usr/share/postfixadmin/public

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/admin.$DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/admin.$DOMAIN/privkey.pem

    <Directory /usr/share/postfixadmin/public>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/postfixadmin_error.log
    CustomLog \${APACHE_LOG_DIR}/postfixadmin_access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerAdmin webmaster@$DOMAIN
    ServerName mail.$DOMAIN
    DocumentRoot /var/lib/roundcube

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/mail.$DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/mail.$DOMAIN/privkey.pem

    <Directory /var/lib/roundcube>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/roundcube_error.log
    CustomLog \${APACHE_LOG_DIR}/roundcube_access.log combined
</VirtualHost>
EOF

# Habilitar módulos necesarios
a2enmod ssl
a2enmod headers
a2enmod rewrite

# Reiniciar Apache
systemctl restart apache2
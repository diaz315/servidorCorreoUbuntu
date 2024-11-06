#!/bin/bash

# Variables
DOMAIN="jdtech.com.co"
HOSTNAME="mail.$DOMAIN"

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

# Hacer backup de configuraciones actuales
print_message "Haciendo backup de configuraciones..."
mkdir -p /root/apache_backup
cp -r /etc/apache2/sites-available/* /root/apache_backup/
cp -r /etc/apache2/sites-enabled/* /root/apache_backup/

# Deshabilitar todos los sitios actuales
print_message "Deshabilitando configuraciones actuales..."
a2dissite *

# Crear configuraciones separadas para cada dominio
print_message "Creando nuevas configuraciones de Apache..."

# Configuración para el dominio principal
cat > /etc/apache2/sites-available/000-$DOMAIN.conf << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAdmin webmaster@$DOMAIN
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

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined
</VirtualHost>
EOF

# Configuración para el subdominio admin
cat > /etc/apache2/sites-available/admin.$DOMAIN.conf << EOF
<VirtualHost *:80>
    ServerName admin.$DOMAIN
    ServerAdmin webmaster@$DOMAIN
    DocumentRoot /usr/share/postfixadmin/public

    <Directory /usr/share/postfixadmin/public>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/admin_${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/admin_${DOMAIN}_access.log combined
</VirtualHost>
EOF

# Configuración para el subdominio mail
cat > /etc/apache2/sites-available/mail.$DOMAIN.conf << EOF
<VirtualHost *:80>
    ServerName mail.$DOMAIN
    ServerAdmin webmaster@$DOMAIN
    DocumentRoot /var/lib/roundcube

    <Directory /var/lib/roundcube>
        Options FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/mail_${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/mail_${DOMAIN}_access.log combined
</VirtualHost>
EOF

# Habilitar las nuevas configuraciones
print_message "Habilitando nuevas configuraciones..."
a2ensite 000-$DOMAIN.conf
a2ensite admin.$DOMAIN.conf
a2ensite mail.$DOMAIN.conf

# Verificar sintaxis de Apache
print_message "Verificando sintaxis de Apache..."
apache2ctl configtest

if [ $? -ne 0 ]; then
    print_error "Error en la configuración de Apache. Restaurando backup..."
    rm -f /etc/apache2/sites-available/*
    cp -r /root/apache_backup/* /etc/apache2/sites-available/
    exit 1
fi

# Limpiar cualquier certificado existente
print_message "Limpiando certificados anteriores..."
certbot delete --cert-name $DOMAIN --non-interactive || true
rm -rf /etc/letsencrypt/live/$DOMAIN*
rm -rf /etc/letsencrypt/archive/$DOMAIN*
rm -rf /etc/letsencrypt/renewal/$DOMAIN*

# Reiniciar Apache antes de obtener certificados
print_message "Reiniciando Apache..."
systemctl restart apache2

# Obtener certificados de manera individual
print_message "Obteniendo certificados SSL..."

# Dominio principal
print_message "Configurando dominio principal..."
certbot --apache -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN

# Subdominio mail
print_message "Configurando subdominio mail..."
certbot --apache -d mail.$DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN

# Subdominio admin
print_message "Configurando subdominio admin..."
certbot --apache -d admin.$DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN

# Verificar la configuración de Apache
print_message "Verificando configuración final de Apache..."
apache2ctl -S

# Reiniciar servicios
print_message "Reiniciando servicios..."
systemctl restart apache2
systemctl restart postfix
systemctl restart dovecot

# Verificación final
print_message "Verificando servicios..."
if systemctl is-active --quiet apache2 && \
   systemctl is-active --quiet postfix && \
   systemctl is-active --quiet dovecot; then
    print_message "Todos los servicios están funcionando correctamente"
else
    print_error "Algunos servicios no están funcionando correctamente"
fi

print_message "Verificación de certificados..."
certbot certificates

print_message "Proceso completado. Verifica los siguientes puntos:"
print_message "1. Acceso a https://$DOMAIN"
print_message "2. Acceso a https://mail.$DOMAIN"
print_message "3. Acceso a https://admin.$DOMAIN"
print_message ""
print_message "Si encuentras algún error, puedes:"
print_message "1. Revisar los logs: tail -f /var/log/letsencrypt/letsencrypt.log"
print_message "2. Revisar la configuración de Apache: apache2ctl -S"
print_message "3. Verificar los certificados: certbot certificates"
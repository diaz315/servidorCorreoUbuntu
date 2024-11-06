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

print_message "¡Corrección completada!"
print_message "Por favor, verifica que ahora puedes acceder correctamente a los recursos estáticos de Roundcube"
print_message "Si continúas teniendo problemas, verifica los logs de Apache en /var/log/apache2/error.log"
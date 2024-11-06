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

print_message "¡Corrección completada!"
print_message "Verifica los logs de Apache si persisten los problemas:"
print_message "tail -f /var/log/apache2/error.log"
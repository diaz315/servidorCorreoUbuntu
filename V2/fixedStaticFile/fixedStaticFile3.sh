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

print_message "¡Corrección completada!"
print_message "Verifica los permisos ejecutando: ls -l /var/lib/roundcube/skins/elastic/deps/"
print_message "Si persisten los problemas, verifica los logs: tail -f /var/log/apache2/error.log"
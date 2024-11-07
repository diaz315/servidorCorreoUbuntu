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

print_message "Corrigiendo acceso a imágenes de Roundcube..."

# 1. Crear estructura de directorios para imágenes
print_message "Creando estructura de directorios para imágenes..."
mkdir -p /var/lib/roundcube/skins/elastic/images

# 2. Copiar favicon y otras imágenes
print_message "Copiando imágenes..."
cp -rf /usr/share/roundcube/skins/elastic/images/* /var/lib/roundcube/skins/elastic/images/

# 3. Establecer permisos correctos
print_message "Estableciendo permisos..."
find /var/lib/roundcube/skins/elastic/images -type d -exec chmod 755 {} \;
find /var/lib/roundcube/skins/elastic/images -type f -exec chmod 644 {} \;

# 4. Establecer propietario correcto
print_message "Estableciendo propietario..."
chown -R www-data:www-data /var/lib/roundcube/skins/elastic/images

# 5. Actualizar configuración de Apache para imágenes
print_message "Actualizando configuración de Apache..."
cat > /etc/apache2/conf-available/roundcube-images.conf << EOF
<Directory /var/lib/roundcube/skins/elastic/images>
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

# Configuración específica para tipos de archivos de imagen
<FilesMatch "\.(ico|png|jpg|jpeg|gif|svg)$">
    Header set Cache-Control "max-age=7200, public"
</FilesMatch>

# Regla específica para favicon
<Location /webmail/skins/elastic/images/favicon.ico>
    Require all granted
</Location>
EOF

# 6. Habilitar la nueva configuración
print_message "Habilitando nueva configuración..."
a2enconf roundcube-images

# 7. Verificar que el favicon existe
print_message "Verificando favicon..."
if [ -f "/var/lib/roundcube/skins/elastic/images/favicon.ico" ]; then
    print_message "✓ Favicon encontrado"
else
    print_error "✗ Favicon no encontrado - copiando de nuevo"
    cp /usr/share/roundcube/skins/elastic/images/favicon.ico /var/lib/roundcube/skins/elastic/images/
fi

# 8. Asegurar que los módulos necesarios están habilitados
print_message "Verificando módulos de Apache..."
a2enmod headers
a2enmod mime

# 9. Agregar tipos MIME específicos si no existen
print_message "Configurando tipos MIME..."
if ! grep -q "image/x-icon" /etc/mime.types; then
    echo "image/x-icon ico" >> /etc/mime.types
fi

# 10. Reiniciar Apache
print_message "Reiniciando Apache..."
systemctl restart apache2

# 11. Verificación final
print_message "Verificando permisos del favicon..."
ls -l /var/lib/roundcube/skins/elastic/images/favicon.ico

print_message "¡Corrección completada!"
print_message "Para verificar que todo está correcto, intenta acceder a:"
print_message "http://tudominio.com/webmail/skins/elastic/images/favicon.ico"
print_message ""
print_message "Si aún hay problemas, verifica los logs de Apache:"
print_message "tail -f /var/log/apache2/error.log"
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
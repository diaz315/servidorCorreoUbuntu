#!/bin/bash

# Variables
DOMAIN="mail.jdtech.com.co"
EMAIL="diazjose195@gmail.com"  # Cambia esto por tu email
ROUNDCUBE_CONF="/etc/apache2/conf-enabled/roundcube.conf"

# Verificar permisos de root
if [ "$EUID" -ne 0 ]; then 
    echo "Por favor ejecuta el script como root"
    exit 1
fi

# Instalar Certbot
install_certbot() {
    apt-get update
    apt-get install -y certbot python3-certbot-apache
}

# Configurar Apache para Roundcube
configure_apache() {
    # Habilitar módulos necesarios
    a2enmod ssl
    a2enmod headers
}

# Obtener y configurar certificado SSL
setup_ssl() {
    # Obtener certificado SSL con Certbot
    certbot --apache \
        --non-interactive \
        --agree-tos \
        --email $EMAIL \
        --domains $DOMAIN \
        --redirect \
        --keep-until-expiring \
        --expand

    # Verificar que la renovación automática está configurada
    systemctl status certbot.timer
}

# Configurar Roundcube para HTTPS
configure_roundcube_https() {
    # Asegurarse de que el archivo de configuración existe
    RCUBE_CONFIG="/etc/roundcube/config.inc.php"
    
    if [ -f "$RCUBE_CONFIG" ]; then
        # Agregar/actualizar configuraciones de HTTPS
        sed -i "/^\$config\['force_https'\]/d" $RCUBE_CONFIG
        sed -i "/^\$config\['use_https'\]/d" $RCUBE_CONFIG
        echo "\$config['force_https'] = true;" >> $RCUBE_CONFIG
        echo "\$config['use_https'] = true;" >> $RCUBE_CONFIG
        
        # Asegurarse de que los permisos son correctos
        chown www-data:www-data $RCUBE_CONFIG
        chmod 640 $RCUBE_CONFIG
    fi
}

# Verificar la existencia del directorio public_html
check_directories() {
    if [ ! -d "/var/lib/roundcube/public_html" ]; then
        echo "Error: El directorio /var/lib/roundcube/public_html no existe"
        echo "Verificando la estructura de directorios de Roundcube..."
        ls -la /var/lib/roundcube
        exit 1
    fi
}

# Función principal
main() {
    echo "Iniciando configuración SSL para Roundcube..."
    
    # Verificar directorios
    check_directories
    
    # Instalar Certbot
    install_certbot
    
    # Configurar Apache
    configure_apache
    
    # Configurar SSL
    setup_ssl
    
    # Configurar Roundcube para HTTPS
    configure_roundcube_https
    
    # Reiniciar Apache
    systemctl restart apache2
    
    echo "¡Configuración completada!"
    echo "Roundcube está disponible en: https://$DOMAIN/roundcube"
    echo "La renovación del certificado SSL es automática mediante el timer de systemd"
    
    # Mostrar estado de los servicios
    echo -e "\nEstado de Apache:"
    systemctl status apache2 --no-pager
    
    echo -e "\nEstado del timer de Certbot:"
    systemctl status certbot.timer --no-pager
    
    # Probar la renovación (en modo dry-run)
    echo -e "\nProbando la renovación automática (dry-run):"
    certbot renew --dry-run
}

# Ejecutar función principal
main
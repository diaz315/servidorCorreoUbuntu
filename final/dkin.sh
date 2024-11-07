#!/bin/bash

# Variables
DOMAIN="jdtech.com.co"  # Reemplaza con tu dominio
SELECTOR="mail"         # Selector para DKIM

# Instalar OpenDKIM
install_opendkim() {
    apt-get update
    apt-get install -y opendkim opendkim-tools
}

# Función para limpiar el formato de la clave DKIM
clean_dkim_key() {
    local file="$1"
    # Extrae solo la parte necesaria del registro TXT y la formatea correctamente
    grep -o '".*"' "$file" | tr -d '\n' | sed 's/"//g' | sed 's/)\s\+(//' | sed 's/\s\+//g'
}

# Configurar OpenDKIM
configure_opendkim() {
    # Crear directorios necesarios
    mkdir -p /etc/opendkim/keys/$DOMAIN
    
    # Configurar OpenDKIM
    cat > /etc/opendkim.conf << EOF
AutoRestart             Yes
AutoRestartRate         10/1h
UMask                  002
Syslog                 yes
SyslogSuccess          Yes
LogWhy                 Yes

Canonicalization       relaxed/simple

ExternalIgnoreList     refile:/etc/opendkim/TrustedHosts
InternalHosts          refile:/etc/opendkim/TrustedHosts
KeyTable               refile:/etc/opendkim/KeyTable
SigningTable           refile:/etc/opendkim/SigningTable

Mode                   sv
PidFile               /var/run/opendkim/opendkim.pid
SignatureAlgorithm    rsa-sha256

UserID                opendkim:opendkim
Socket                inet:12301@localhost
EOF

    # Configurar TrustedHosts
    cat > /etc/opendkim/TrustedHosts << EOF
127.0.0.1
localhost
*.$DOMAIN
EOF

    # Configurar KeyTable
    echo "mail._domainkey.$DOMAIN $DOMAIN:mail:/etc/opendkim/keys/$DOMAIN/mail.private" > /etc/opendkim/KeyTable

    # Configurar SigningTable
    echo "*@$DOMAIN mail._domainkey.$DOMAIN" > /etc/opendkim/SigningTable

    # Generar claves DKIM
    cd /etc/opendkim/keys/$DOMAIN
    opendkim-genkey -s mail -d $DOMAIN
    chown opendkim:opendkim mail.private

    # Mostrar la clave pública en el formato deseado
    echo "============================================"
    echo "Configura este registro TXT en tu DNS:"
    echo "============================================"
    echo "Nombre del registro: mail._domainkey"
    echo "Tipo: TXT"
    echo "Valor:"
    echo -n "v=DKIM1; h=sha256; k=rsa; p="
    clean_dkim_key mail.txt | grep -o 'p=.*' | cut -d'=' -f2
    echo "============================================"
}

# Configurar Postfix para usar DKIM
configure_postfix_dkim() {
    # Añadir configuración DKIM a Postfix
    cat >> /etc/postfix/main.cf << EOF

# DKIM
milter_protocol = 2
milter_default_action = accept
smtpd_milters = inet:localhost:12301
non_smtpd_milters = inet:localhost:12301
EOF

    # Reiniciar servicios
    systemctl restart opendkim postfix
}

# Función principal
main() {
    install_opendkim
    configure_opendkim
    configure_postfix_dkim
    
    echo "Configuración de DKIM completada!"
    echo "Por favor, agrega el registro TXT mostrado arriba en tu configuración DNS"
}

# Verificar si se ejecuta como root
if [ "$(id -u)" != "0" ]; then
    echo "Este script debe ejecutarse como root"
    exit 1
fi

# Ejecutar función principal
main
#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Solicitar datos del usuario
read -p "Ingrese el email completo del usuario: " EMAIL
read -s -p "Ingrese la contraseña para el usuario: " PASSWORD
echo

# Validar que se ingresaron los datos
if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
    echo "Error: El email y la contraseña son obligatorios"
    exit 1
fi

# Obtener el dominio del email
DOMAIN=$(echo "$EMAIL" | cut -d "@" -f 2)

# Generar hash de la contraseña usando doveadm
HASHED_PASSWORD=$(doveadm pw -s SHA512-CRYPT -p "$PASSWORD")

# Verificar si la generación del hash fue exitosa
if [ $? -ne 0 ]; then
    echo "Error al generar el hash de la contraseña"
    exit 1
fi

# Obtener el domain_id de la base de datos
DOMAIN_ID=$(mysql -N mailserver -e "SELECT id FROM virtual_domains WHERE name='$DOMAIN';")

# Verificar si el dominio existe
if [ -z "$DOMAIN_ID" ]; then
    echo "Error: El dominio $DOMAIN no existe en la base de datos"
    echo "¿Desea crear el dominio? (s/n)"
    read CREATE_DOMAIN
    
    if [ "$CREATE_DOMAIN" = "s" ] || [ "$CREATE_DOMAIN" = "S" ]; then
        mysql mailserver -e "INSERT INTO virtual_domains (name) VALUES ('$DOMAIN');"
        DOMAIN_ID=$(mysql -N mailserver -e "SELECT id FROM virtual_domains WHERE name='$DOMAIN';")
        echo "Dominio creado con ID: $DOMAIN_ID"
    else
        exit 1
    fi
fi

# Insertar el usuario en la base de datos
mysql mailserver << EOF
INSERT INTO virtual_users (domain_id, email, password) 
VALUES ($DOMAIN_ID, '$EMAIL', '$HASHED_PASSWORD');
EOF

# Verificar si la inserción fue exitosa
if [ $? -eq 0 ]; then
    echo "Usuario creado exitosamente:"
    echo "Email: $EMAIL"
    echo "Domain ID: $DOMAIN_ID"
else
    echo "Error al crear el usuario en la base de datos"
    exit 1
fi

# Mostrar los usuarios actuales en el dominio
echo -e "\nUsuarios actuales en el dominio $DOMAIN:"
mysql mailserver -e "SELECT email FROM virtual_users WHERE domain_id=$DOMAIN_ID;"
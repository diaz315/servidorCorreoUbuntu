#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Set domain name
DOMAIN="jdtech.com.co"

# Generate random DES key
DES_KEY=$(openssl rand -base64 18)

# Install required packages
echo "Installing required packages..."
apt-get update
apt-get install -y \
    roundcube \
    roundcube-mysql \
    roundcube-core \
    php-zip \
    php-imagick \
    php-mysql \
    php-xml \
    php-mbstring \
    php-curl \
    roundcube-plugins

# Backup original config if exists
if [ -f /etc/roundcube/config.inc.php ]; then
    mv /etc/roundcube/config.inc.php /etc/roundcube/config.inc.php.bak
fi

# Create Roundcube configuration
cat > /etc/roundcube/config.inc.php << EOL
<?php
    \$config = [];
    include("/etc/roundcube/debian-db-roundcube.php");
    \$config['imap_host'] = ["localhost:143"];
    \$config['smtp_host'] = 'localhost:587';
    \$config['smtp_auth_type'] = 'PLAIN';
    \$config['smtp_helo_host'] = '$DOMAIN_NAME';
    \$config['default_host'] = 'localhost';
    \$config['smtp_server'] = 'localhost';
    \$config['smtp_port'] = 25;
    \$config['smtp_user'] = '%u';
    \$config['smtp_pass'] = '%p';
    \$config['support_url'] = '';
    \$config['product_name'] = 'Webmail';
    \$config['des_key'] = '$DES_KEY';
    \$config['skin'] = 'elastic';
    \$config['plugins'] = array();
    \$config['language'] = 'es_ES';
    \$config['imap_conn_options'] = array(
        'ssl' => array(
            'verify_peer' => false,
            'verify_peer_name' => false,
        ),
    );
    \$config['smtp_conn_options'] = array(
        'ssl' => array(
            'verify_peer' => false,
            'verify_peer_name' => false,
        ),
    );

    // Default HTML preferences
    \$config['prefer_html'] = true;
    \$config['htmleditor'] = true;
    \$config['prettydate'] = true;
    \$config['preview_pane'] = true;
    \$config['message_show_email'] = true;
    \$config['default_charset'] = 'UTF-8';
    \$config['html_editor'] = true;
    \$config['compose_responses_static'] = false;
    \$config['default_message_format'] = 'html';
    \$config['show_images'] = 1;
    \$config['image_proxy'] = false;
    \$config['compose_html'] = true;
    \$config['compose_html_signatures'] = true;

    // User preferences
    \$config['preferences'] = array(
        'prefer_html' => true,
        'htmleditor' => true,
        'preview_pane' => true,
        'preview_pane_mark_read' => 0,
        'compose_html' => true,
        'show_images' => 1,
        'display_next' => true,
        'default_view' => 'list',
    );

    // HTML editor configuration
    \$config['html_editor_config'] = array(
        'toolbar' => 'basic',
        'spellcheck' => true,
        'default_font' => 'Arial',
        'default_font_size' => '12pt',
        'image_upload' => true,
        'max_image_upload_size' => '5M',
    );

    // Security and display options
    \$config['html_sanitizer'] = true;
    \$config['message_sanitizer'] = true;
    \$config['forward_attachment'] = true;
    \$config['image_thumbnail_size'] = 240;
    \$config['layout'] = 'widescreen';
    \$config['addressbook_sort_col'] = 'name';
    \$config['autoexpand_threads'] = 2;
    \$config['mime_param_folding'] = 0;
    \$config['send_format_flowed'] = true;
    \$config['display_version'] = false;
    \$config['timezone'] = 'America/Bogota';
    \$config['date_format'] = 'Y-m-d H:i';
    \$config['draft_autosave'] = 60;
    \$config['preview_pane_mark_read'] = 0;
    \$config['read_when_deleted'] = true;
    \$config['refresh_interval'] = 60;
EOL

# Set permissions
echo "Setting permissions..."
chown -R www-data:www-data /var/lib/roundcube
chown -R www-data:www-data /etc/roundcube
chmod -R 755 /var/lib/roundcube
chmod -R 755 /etc/roundcube

# Enable Apache alias
echo "Configuring Apache..."
a2enconf roundcube

# Generate SSL certificate
echo "Generating SSL certificate..."
mkdir -p /etc/postfix/ssl
openssl req -new -x509 -days 365 -nodes \
    -out /etc/postfix/ssl/smtp.crt \
    -keyout /etc/postfix/ssl/smtp.key \
    -subj "/C=CO/ST=State/L=City/O=Organization/CN=$DOMAIN_NAME"

# Set SSL certificate permissions
chmod 600 /etc/postfix/ssl/*
chown postfix:postfix /etc/postfix/ssl/*

# Configure Postfix master.cf
cat > /etc/postfix/master.cf << 'EOL'
# SMTP server
smtp      inet  n       -       y       -       -       smtpd

# SMTP submission
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=may
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_tls_auth_only=no
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

# SMTPS submission (port 465)
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

# Postfix services
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -      y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
  -o syslog_name=postfix/$service_name
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
postlog   unix-dgram n  -       n       -       1       postlogd
EOL

# Restart services
echo "Restarting services..."
systemctl restart postfix dovecot apache2

# Check services status
echo "Checking services status..."
systemctl status apache2 --no-pager
systemctl status postfix --no-pager
systemctl status dovecot --no-pager

echo "Installation complete! Please check the services status above for any errors."
EOL
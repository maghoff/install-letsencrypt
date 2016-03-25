#!/bin/bash

ACME_TINY="https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py"

set -e
set -o pipefail

# `letsencrypt` user will own relevant files and execute certificate renewal script
#
# `letsencrypt` user does not need access to your private domain key, and should not
# be allowed access to it.
useradd --system letsencrypt

# Working stuff goes in /var/..., generated certs go in /etc/...
mkdir -p /var/letsencrypt /var/www/challenges /etc/ssl/certs/letsencrypt
chown letsencrypt:letsencrypt /var/letsencrypt /var/www/challenges /etc/ssl/certs/letsencrypt
chmod 0700 /var/letsencrypt

# Use acme_tiny for getting certificates signed
curl -L -o /var/letsencrypt/acme_tiny.py "$ACME_TINY"

# RSA key for encrypting communication with Let's Encrypt's servers
openssl genrsa 4096 > /var/letsencrypt/account.key

# The renewal script needs to be able to ask nginx to reload its config
echo "Locking /etc/sudoers for edit..."
lockfile /etc/sudoers.tmp
cp /etc/sudoers /etc/sudoers.letsencrypt.tmp
echo "letsencrypt ALL=(root) NOPASSWD: /usr/sbin/service nginx reload" >> /etc/sudoers.letsencrypt.tmp
visudo -c -f /etc/sudoers.letsencrypt.tmp # Due to `set -e`, brings down the whole script on syntax errors
mv /etc/sudoers.letsencrypt.tmp /etc/sudoers
rm -f /etc/sudoers.tmp
echo "Added letsencrypt to sudoers for automatic reloading of nginx config"


# This is the script we will use for adding new sites
cat > /var/letsencrypt/add.sh <<EOF_ADD
#!/bin/bash

# This script must be run as root

# TODO: Deal with command line arguments
CN="\$1"
KEY="\$2"

# Use for helpful error message if \$KEY is missing:
# #generate a domain private key (if you haven't already)
# openssl genrsa 4096 > /etc/ssl/private/\$CN.key

# Generate certificate signing request
openssl req -new -sha256 -key "\$KEY" -subj "/CN=\$CN" > /var/letsencrypt/\$CN.csr

# Configure nginx to be able to respond to ACME challenges
cat > /etc/nginx/sites-available/letsencrypt-\$CN <<EOF
server {
    listen 80;
    server_name \$CN;

    location /.well-known/acme-challenge/ {
        alias /var/www/challenges/;
        try_files \\$uri =404;
    }
}
EOF
ln -s /etc/nginx/sites-available/letsencrypt-\$CN /etc/nginx/sites-enabled/

# Automatically renew every month at a randomized time
DAY=\$(( ( RANDOM % 28 )  + 1 ))
MINUTE=\$(( RANDOM % 60 ))
(crontab -l -u letsencrypt 2>/dev/null; echo "\$MINUTE 0 \$DAY * * /var/letsencrypt/update.sh \$CN") | crontab -u letsencrypt -

service nginx reload

sudo -u letsencrypt /var/letsencrypt/update.sh \$CN
EOF_ADD
chmod a+x /var/letsencrypt/add.sh


# This is the script we will use for automatic renewals
cat > /var/letsencrypt/update.sh <<EOF
#!/bin/bash

CN="\$1"

set -e

/usr/bin/python \
        /var/letsencrypt/acme_tiny.py \
        --account-key /var/letsencrypt/account.key \
        --csr "/var/letsencrypt/\$CN.csr" \
        --acme-dir /var/www/challenges/ \
        > "/var/letsencrypt/\$CN.crt"

curl 'https://letsencrypt.org/certs/lets-encrypt-x1-cross-signed.pem' > /var/letsencrypt/intermediate.pem

cat /var/letsencrypt/\$CN.crt /var/letsencrypt/intermediate.pem > /etc/ssl/certs/letsencrypt/\$CN.pem

sudo /usr/sbin/service nginx reload
EOF
chmod a+x /var/letsencrypt/update.sh


echo
echo "Successfully installed tools"
echo "Now, as root, run"
echo "    /var/letsencrypt/add.sh domain.name /etc/ssl/private/domain.name.key"

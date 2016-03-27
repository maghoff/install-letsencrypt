#!/bin/bash

ACME_TINY="https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py"

set -e
set -o pipefail

command -v openssl >/dev/null 2>&1 || { echo >&2 "I require openssl but it's not installed"; exit 1; }
command -v lockfile >/dev/null 2>&1 || { echo >&2 "I require lockfile but it's not installed. Try installing procmail"; exit 1; }

# `letsencrypt` user will own relevant files and execute certificate renewal script
#
# `letsencrypt` user does not need access to your private domain key, and should not
# be allowed access to it.
if ! getent passwd letsencrypt > /dev/null
then
	useradd --system letsencrypt
fi

# Working stuff goes in /var/..., generated certs go in /etc/...
mkdir -p /var/letsencrypt /var/www/challenges /etc/ssl/certs/letsencrypt
chown letsencrypt:letsencrypt /var/letsencrypt /var/www/challenges /etc/ssl/certs/letsencrypt
chmod 0700 /var/letsencrypt

# Use acme_tiny for getting certificates signed
curl -L -o /var/letsencrypt/acme_tiny.py "$ACME_TINY"

# RSA key for encrypting communication with Let's Encrypt's servers
if [ ! -f /var/letsencrypt/account.key ]
then
	echo "Generating account.key..."
	openssl genrsa 4096 > /var/letsencrypt/account.key
fi

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

if [ \$# -lt 1 ] || [ \$# -gt 2 ]
then
	echo >&2 "Usage: \$0 domain-name [key-file]"
	echo >&2
	echo >&2 "If key-file is not specified it will default to"
	echo >&2 "    /etc/ssl/private/domain-name.key"
	echo >&2
	echo >&2 "If key-file does not exist, it will be generated like this"
	echo >&2 "    openssl genrsa 4096 > key-file"
	exit 1
fi

CN="\$1"

if [ \$# -eq 2 ]
then
	KEY="\$2"
else
	KEY="/etc/ssl/private/\$CN"
fi

if [ ! -f "\$KEY" ]
then
	echo "Generating key file \$KEY..."
	openssl genrsa 4096 > \$KEY
fi

# Generate certificate signing request
openssl req -new -sha256 -key "\$KEY" -subj "/CN=\$CN" > /var/letsencrypt/\$CN.csr

# Configure nginx to be able to respond to ACME challenges
cat > /etc/nginx/sites-available/letsencrypt-\$CN <<EOF
server {
    listen 80;
    server_name \$CN;

    location /.well-known/acme-challenge/ {
        alias /var/www/challenges/;
        try_files \\\$uri =404;
    }

    location / {
        return 308 https://\$host\$request_uri;
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

echo
echo "Generated Let's Encrypt signed certificate. Use the following in your nginx config:"
echo "    ssl on;"
echo "    ssl_certificate /etc/ssl/certs/letsencrypt/\$CN.pem;"
echo "    ssl_certificate_key \$KEY;"
EOF_ADD
chmod a+x /var/letsencrypt/add.sh


# This is the script we will use for automatic renewals
cat > /var/letsencrypt/update.sh <<EOF
#!/bin/bash

CN="\$1"
INTERMEDIATE="https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem"

set -e

(
	/usr/bin/python \\
			/var/letsencrypt/acme_tiny.py \\
			--account-key /var/letsencrypt/account.key \\
			--csr "/var/letsencrypt/\$CN.csr" \\
			--acme-dir /var/www/challenges/
	curl "\$INTERMEDIATE"
) > /etc/ssl/certs/letsencrypt/\$CN.pem

sudo /usr/sbin/service nginx reload
EOF
chmod a+x /var/letsencrypt/update.sh


echo
echo "Successfully installed tools"
echo "Now, as root, run"
echo "    /var/letsencrypt/add.sh domain.name /etc/ssl/private/domain.name.key"

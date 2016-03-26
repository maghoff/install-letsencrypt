Install Let's Encrypt
=====================
This project aims to make it easy to deploy Let's Encrypt validated certificates
to your servers for any number of sites, including automatic renewal.

It is only intended to work if you are running nginx as your web server and it
has only been tested to work on Ubuntu.

Dependencies
------------
`openssl`, `curl`, `nginx` and, surprisingly, `procmail`.

`procmail` comes with `lockfile`, which is used for safely editing
`/etc/sudoers`. There is [an issue for getting rid of this dependency][#1].

[#1]: https://github.com/maghoff/install-letsencrypt/issues/1

Install
-------
If you have verified the script and you trust github or you simply don't like
security:

    curl -L \
        https://raw.githubusercontent.com/maghoff/install-letsencrypt/master/install.sh \
        | sudo bash

Otherwise:

 1. Download [`install.sh`](https://raw.githubusercontent.com/maghoff/install-letsencrypt/master/install.sh):

        curl -LO https://raw.githubusercontent.com/maghoff/install-letsencrypt/master/install.sh

 2. Read through it and verify that you trust it, or hire somebody to do this
    job for you.

 3. Then, execute the script as root: `sudo bash install.sh`

Usage
-----
After install, you can add a site. Assuming you have a private key for your
domain in `/etc/ssl/private/example.com.key`, run:

    sudo /var/letsencrypt/add.sh example.com /etc/ssl/private/example.com.key

(If you don't already have a private key, run
`openssl genrsa 4096 > /etc/ssl/private/example.com.key`)

Now, use `/etc/ssl/certs/letsencrypt/example.com.pem` as the certificate in your
nginx config:

    ssl on;
    ssl_certificate /etc/ssl/certs/letsencrypt/example.com.pem;
    ssl_certificate_key /etc/ssl/private/example.com.key;

The certificate will be updated automatically every month.

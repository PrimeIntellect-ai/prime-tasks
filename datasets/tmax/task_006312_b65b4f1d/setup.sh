#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl zip unzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/webroot/css
    mkdir -p /home/user/webroot/js
    touch /home/user/webroot/index.html
    touch /home/user/webroot/css/style.css
    touch /home/user/webroot/js/app.js
    chmod -R 777 /home/user/webroot/

    cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 +0000] "GET /index.html HTTP/1.1" 200 1024
192.168.1.11 - - [10/Oct/2023:13:56:01 +0000] "GET /login?redirect=aHR0cHM6Ly9ldmlsLWNvcnAuY29tL3N0ZWFs HTTP/1.1" 302 -
192.168.1.12 - - [10/Oct/2023:13:57:12 +0000] "GET /login?redirect=aHR0cDovL2F0dGFja2VyLnNpdGUvY3JlZHM= HTTP/1.1" 302 -
192.168.1.11 - - [10/Oct/2023:13:58:22 +0000] "GET /login?redirect=aHR0cHM6Ly9ldmlsLWNvcnAuY29tL3N0ZWFs HTTP/1.1" 302 -
EOF

    cat << 'EOF' > /home/user/wordlist.txt
password123
qwerty
letmein
admin123
hacker
EOF

    echo "SuperSecretKey999" > /home/user/key.txt
    echo "FLAG{0p3n_r3dir3ct_r3s0lv3d}" > /home/user/payload.txt
    openssl enc -aes-256-cbc -pbkdf2 -salt -in /home/user/payload.txt -out /home/user/payload.enc -pass pass:SuperSecretKey999

    cd /home/user
    zip --password admin123 exfiltrated.zip key.txt payload.enc
    rm key.txt payload.txt payload.enc

    chmod -R 777 /home/user

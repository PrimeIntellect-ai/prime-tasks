#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/certs

    cat << 'EOF' > /home/user/legacy.conf
server_port: 8080
db_user: admin
db_password_hash: 5f4dcc3b5aa765d61d8327deb882cf99
EOF

    cat << 'EOF' > /home/user/wordlist.txt
admin
123456
admin123
password
qwerty
iloveyou
EOF

    cat << 'EOF' > /home/user/app.log
[INFO] Application started
[DEBUG] Connecting to AWS with key AKIAIOSFODNN7EXAMPLE for bucket access.
[INFO] User logged in.
[DEBUG] Backup completed. Used credentials: AKIAB1C2D3E4F5G6H7I8 to store payload.
[ERROR] Failed to connect.
EOF

    openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/legacy.key -out /home/user/certs/legacy.crt -days 1 -nodes -subj "/CN=legacy.local"

    chown -R user:user /home/user
    chmod -R 777 /home/user

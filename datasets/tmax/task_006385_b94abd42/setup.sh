#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident_response/new_keys

    cat << 'EOF' > /home/user/incident_response/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36] "GET /upload?file=../../../../etc/passwd HTTP/1.1" 200
192.168.1.11 - - [10/Oct/2023:13:56:01] "POST /login?password=Secret123Password HTTP/1.1" 401
192.168.1.12 - - [10/Oct/2023:13:57:22] "GET /api/data HTTP/1.1" 200 - "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
192.168.1.10 - - [10/Oct/2023:13:58:36] "GET /upload?file=../../../../home/user/.ssh/id_rsa HTTP/1.1" 200
EOF

    cat << 'EOF' > /tmp/config_plaintext.txt
APP_ENV=production
DB_HOST=10.0.0.5
DB_USER=admin
DB_PASSWORD=OldCompromisedDBPass!
API_KEY=xyz123
EOF

    openssl enc -aes-256-cbc -pbkdf2 -pass pass:compromised_pass_123 -in /tmp/config_plaintext.txt -out /home/user/incident_response/config.enc

    cat << 'EOF' > /home/user/incident_response/sshd_config
# This is a test sshd_config
Port 22
PermitRootLogin yes
#PasswordAuthentication yes
X11Forwarding yes
EOF

    chown -R user:user /home/user/incident_response
    chmod -R 777 /home/user

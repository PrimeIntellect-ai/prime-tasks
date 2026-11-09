#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc openssl coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the raw audit log
    cat << 'EOF' > /home/user/raw_audit.log
User admin logged in from 192.168.1.100
Running setup script
sudo chown root:root /etc/myapp
chmod 777 /etc/myapp/config
Connecting to database at 10.0.0.5
EOF

    # Base64 encode it
    base64 /home/user/raw_audit.log > /home/user/audit_log.b64
    rm /home/user/raw_audit.log

    # Create a dummy certificate
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=test.local" \
        -keyout /home/user/server.key -out /home/user/server.crt 2>/dev/null

    chmod -R 777 /home/user

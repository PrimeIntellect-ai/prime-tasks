#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deployment

    # 1. Create App.py with CWEs
    cat << 'EOF' > /home/user/deployment/app.py
import os

DB_PASS = "admin123" # CWE-798

def run_ping(ip):
    # Vulnerable to OS Command Injection
    os.system("ping -c 1 " + ip) # CWE-78

if __name__ == "__main__":
    run_ping("127.0.0.1")
EOF

    # 2. Create sshd_config (Not hardened)
    cat << 'EOF' > /home/user/deployment/sshd_config
Port 22
PermitRootLogin yes
PasswordAuthentication no
EOF

    # 3. Create utils.js and manifest.sha256 (Hash mismatch)
    echo "console.log('original code');" > /home/user/deployment/utils.js
    echo "console.log('secure config');" > /home/user/deployment/config.js

    cd /home/user/deployment
    sha256sum app.py sshd_config utils.js config.js > manifest.sha256

    # Tamper with utils.js
    echo "console.log('tampered code');" > /home/user/deployment/utils.js

    # 4. Generate Certificates (Invalid chain)
    openssl req -x509 -nodes -days 365 -subj "/CN=RealCA" -newkey rsa:2048 -keyout /tmp/real_ca.key -out /home/user/deployment/ca.pem 2>/dev/null
    openssl req -x509 -nodes -days 365 -subj "/CN=FakeCA" -newkey rsa:2048 -keyout /tmp/fake_ca.key -out /tmp/fake_ca.pem 2>/dev/null
    openssl req -new -nodes -subj "/CN=App" -newkey rsa:2048 -keyout /tmp/app.key -out /tmp/app.csr 2>/dev/null
    openssl x509 -req -in /tmp/app.csr -CA /tmp/fake_ca.pem -CAkey /tmp/fake_ca.key -CAcreateserial -out /home/user/deployment/cert.pem -days 365 2>/dev/null

    chown -R user:user /home/user/deployment
    chmod -R 777 /home/user

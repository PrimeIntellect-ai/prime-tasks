#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    # Generate Fernet key
    python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode('utf-8'))" > /home/user/fernet.key

    # Create auth_mock.py
    cat << 'EOF' > /home/user/auth_mock.py
import sys
import base64

if len(sys.argv) != 2:
    sys.exit(1)

token = sys.argv[1]
try:
    decoded = base64.b64decode(token).decode('utf-8')
except:
    sys.exit(1)

valid_secrets = ["admin:supersecret123", "root:toor"]
if decoded in valid_secrets:
    sys.exit(0)
else:
    sys.exit(1)
EOF

    # Create repo directory and conf files
    mkdir -p /home/user/repo

    cat << 'EOF' > /home/user/repo/app1.conf
Server=192.168.1.10
Authorization: Basic YWRtaW46c3VwZXJzZWNyZXQxMjM=
Port=8080
EOF

    cat << 'EOF' > /home/user/repo/app2.conf
Server=10.0.0.5
Authorization: Basic Z3Vlc3Q6Z3Vlc3Q=
Timeout=30
EOF

    cat << 'EOF' > /home/user/repo/app3.conf
Host=localhost
Authorization: Basic cm9vdDp0b29y
EOF

    chmod -R 777 /home/user

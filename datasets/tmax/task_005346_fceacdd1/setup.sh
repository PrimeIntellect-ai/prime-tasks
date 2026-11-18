#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest PyJWT

    mkdir -p /home/user/app/logs
    mkdir -p /home/user/app/config
    mkdir -p /home/user/app/old_keys
    mkdir -p /home/user/incident_report

    # 1. Create logs
    cat << 'EOF' > /home/user/app/logs/auth.log
{"timestamp": "2023-10-01T12:00:00Z", "ip": "192.168.1.50", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiam9obiIsInJvbGUiOiJ1c2VyIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"}
{"timestamp": "2023-10-01T12:05:00Z", "ip": "10.13.37.99", "token": "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYmFkZ3V5Iiwicm9sZSI6ImFkbWluIn0."}
{"timestamp": "2023-10-01T12:10:00Z", "ip": "172.16.0.4", "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWxpY2UiLCJyb2xlIjoidXNlciJ9.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"}
EOF

    # 2. Create initial blocklist
    echo '["198.51.100.23"]' > /home/user/app/config/blocklist.json

    # 3. Create vulnerable python code
    cat << 'EOF' > /home/user/app/auth.py
import jwt

def decode_token(token, secret):
    # Insecure decoding allowing any algorithm including none
    return jwt.decode(token, secret, options={"verify_signature": False})
EOF

    # 4. Create secret
    echo "old_secret_value_12345" > /home/user/app/config/secret.key

    # 5. Create old keys and manifest
    echo "key_v1_content" > /home/user/app/old_keys/key_v1.pem
    echo "key_v2_content" > /home/user/app/old_keys/key_v2.pem
    echo "key_v3_content" > /home/user/app/old_keys/key_v3.pem

    # Generate correct manifest
    cd /home/user/app/old_keys
    sha256sum * > /home/user/app/keys_manifest.sha256

    # Modify key_v2 to simulate tampering
    echo "key_v2_content_backdoored" > /home/user/app/old_keys/key_v2.pem
    cd /

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

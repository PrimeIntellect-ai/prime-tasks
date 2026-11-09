#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit/keys

    cat << 'EOF' > /home/user/audit/sshd_config
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
X11Forwarding no
EOF

    cat << 'EOF' > /home/user/audit/auth_service.py
import sys, json, base64

def authenticate(payload_file):
    with open(payload_file, 'r') as f:
        encoded_data = f.read().strip()

    try:
        decoded_bytes = base64.b64decode(encoded_data)
        data = json.loads(decoded_bytes.decode('utf-8'))

        if data.get('username') == 'auditor' and data.get('role') == 'admin':
            print("AUTH_SUCCESS")
            return True
        else:
            print("AUTH_FAILED")
            return False
    except Exception as e:
        print("AUTH_ERROR")
        return False

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 auth_service.py <payload_file>")
        sys.exit(1)
    authenticate(sys.argv[1])
EOF

    touch /home/user/audit/keys/id_rsa_prod
    touch /home/user/audit/keys/id_rsa_dev
    touch /home/user/audit/keys/id_rsa_weak
    touch /home/user/audit/keys/public.pub

    # Apply global permissions first
    chmod -R 777 /home/user

    # Fix specific key permissions required by the task
    chmod 600 /home/user/audit/keys/id_rsa_prod
    chmod 600 /home/user/audit/keys/id_rsa_dev
    chmod 644 /home/user/audit/keys/id_rsa_weak
    chmod 644 /home/user/audit/keys/public.pub

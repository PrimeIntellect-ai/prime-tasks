#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_handler.py
import hashlib

def verify_admin(pin):
    # Authenticate remote command execution
    salt = b'NET_ENG_2024'
    return hashlib.md5(pin.encode('ascii') + salt).hexdigest()
EOF

    echo -n "e3d7cb76a268b209bd59c824c9c69315" > /home/user/intercepted_hash.txt
    echo -n "MALICIOUS_PACKET_DATA_XYZ_999" > /home/user/payload.bin

    chmod -R 777 /home/user

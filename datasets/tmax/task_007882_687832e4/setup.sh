#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh
    echo "FAKE_PRIVATE_KEY_DATA" > /home/user/.ssh/id_rsa

    cat << 'EOF' > /home/user/legacy_auth.py
import base64

def encode_payload(text: str, key: int = 0x3F) -> str:
    """Legacy weak encryption."""
    xored = bytes([ord(c) ^ key for c in text])
    return base64.b64encode(xored).decode('utf-8')
EOF

    echo -n "PzMzH1w+HBo1A0dEXw8BHEcfDR0fTks=" > /home/user/admin_payload.b64

    chmod -R 777 /home/user

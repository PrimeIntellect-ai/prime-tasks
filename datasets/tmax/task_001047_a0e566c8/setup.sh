#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/custom_session_lib/custom_session_lib
    mkdir -p /home/user

    # Create the broken setup.py
    cat << 'EOF' > /app/custom_session_lib/setup.py
import setuptool

setuptools.setup(
    name="custom_session_lib",
    version="1.0.0",
    packages=["custom_session_lib"]
EOF

    # Create the custom_session_lib code
    cat << 'EOF' > /app/custom_session_lib/custom_session_lib/__init__.py
import binascii
import sys

def _xor(data, key):
    return bytes(a ^ b for a, b in zip(data, key * (len(data) // len(key) + 1)))

def verify_token(token_hex):
    try:
        data = binascii.unhexlify(token_hex)
        decrypted = _xor(data, b"secret42").decode('utf-8')
        if decrypted.startswith("username:") and ",role:" in decrypted:
            return True
        return False
    except Exception:
        # Simulate a memory corruption crash for malformed inputs
        sys.exit(139)
EOF

    # Create the intercepted traffic file
    cat << 'EOF' > /home/user/traffic.txt
[10:45:01] GET /login?redirect=http://attacker.com/steal_token&token=181806080b061c4749121a00181a441e481007071e161100 HTTP/1.1
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user

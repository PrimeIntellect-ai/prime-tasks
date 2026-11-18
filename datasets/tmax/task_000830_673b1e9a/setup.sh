#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create the auth_service.py script, compile it, and remove the source.
    cat << 'EOF' > /home/user/auth_service.py
import base64

def encrypt_log(message):
    key = "c0mpl14nc3"
    encrypted = []
    for i, char in enumerate(message):
        encrypted.append(chr(ord(char) ^ ord(key[i % len(key)])))
    return base64.b64encode("".join(encrypted).encode('utf-8')).decode('utf-8')
EOF

    python3 -m py_compile /home/user/auth_service.py
    mv /home/user/__pycache__/auth_service.*.pyc /home/user/auth_service.pyc
    rm -rf /home/user/__pycache__
    rm /home/user/auth_service.py

    # 2. Generate the encrypted audit log
    python3 -c '
import base64
def encrypt_log(message):
    key = "c0mpl14nc3"
    encrypted = []
    for i, char in enumerate(message):
        encrypted.append(chr(ord(char) ^ ord(key[i % len(key)])))
    return base64.b64encode("".join(encrypted).encode("utf-8")).decode("utf-8")

plaintext_log = """[2023-10-15 08:12:00] SUCCESS User admin logged in.
[2023-10-15 08:45:12] FAILED Login from 192.168.45.10
[2023-10-15 09:02:33] FAILED Login from 10.100.2.55
[2023-10-15 09:15:00] SUCCESS User system_service logged in."""

with open("/home/user/audit_log.enc", "w") as f:
    f.write(encrypt_log(plaintext_log))
'

    chown -R user:user /home/user
    chmod -R 777 /home/user

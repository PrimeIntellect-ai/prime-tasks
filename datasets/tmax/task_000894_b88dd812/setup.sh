#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/deobfuscate.py
import base64

def decrypt_url(obfuscated_str):
    """
    Server-side logic to deobfuscate the redirect_uri.
    """
    # 1. Base64 decode
    decoded = base64.b64decode(obfuscated_str)
    # 2. Reverse the bytes
    reversed_bytes = decoded[::-1]
    # 3. XOR with the static key
    key = b'WAFBypassToken2024'
    decrypted = bytearray()
    for i, b in enumerate(reversed_bytes):
        decrypted.append(b ^ key[i % len(key)])
    return decrypted.decode('utf-8')

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        print(decrypt_url(sys.argv[1]))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

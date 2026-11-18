#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/custom_crypto.py
import sys

def encrypt_data(data, key):
    # Standard multi-byte XOR cipher
    encrypted = bytearray()
    for i in range(len(data)):
        encrypted.append(data[i] ^ key[i % len(key)])
    return encrypted

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python custom_crypto.py <file> <4-byte-key>")
        sys.exit(1)

    with open(sys.argv[1], 'rb') as f:
        data = f.read()

    key = sys.argv[2].encode('utf-8')
    if len(key) != 4:
        raise ValueError("Key must be exactly 4 bytes")

    encrypted = encrypt_data(data, key)
    print(encrypted.hex())
EOF

    echo -n "57fdf0a8d3a7a4e5deadbee297e5fabddeadbeeedeadbeeed6abbeefdeb2ab2b57" > /home/user/captured_traffic.hex

    chmod -R 777 /home/user

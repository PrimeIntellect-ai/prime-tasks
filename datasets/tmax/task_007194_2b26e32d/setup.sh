#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/investigation

    cat << 'EOF' > /home/user/investigation/encryptor.py
import sys
import base64
import itertools

def xor_crypt(data, key):
    return bytes([b ^ k for b, k in zip(data, itertools.cycle(key))])

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python encryptor.py <in_file> <out_file> <2_byte_hex_key>")
        sys.exit(1)

    key = bytes.fromhex(sys.argv[3])
    if len(key) != 2:
        print("Key must be 2 bytes")
        sys.exit(1)

    with open(sys.argv[1], 'rb') as f:
        plaintext = f.read()

    ciphertext = xor_crypt(plaintext, key)
    encoded = base64.b64encode(ciphertext)

    with open(sys.argv[2], 'wb') as f:
        f.write(encoded)
EOF

    python3 -c '
import base64
import itertools
import hashlib

plaintext = b"CONFIDENTIAL_EXFIL_DATA: The vulnerability was in the upload endpoint."
key = bytes.fromhex("7F3A")

def xor_crypt(data, key):
    return bytes([b ^ k for b, k in zip(data, itertools.cycle(key))])

ciphertext = xor_crypt(plaintext, key)
encoded = base64.b64encode(ciphertext)

with open("/home/user/investigation/exfil_data.enc", "wb") as f:
    f.write(encoded)

h = hashlib.sha256(plaintext).hexdigest()
with open("/home/user/investigation/original_hash.txt", "w") as f:
    f.write(h)
'

    chmod -R 777 /home/user

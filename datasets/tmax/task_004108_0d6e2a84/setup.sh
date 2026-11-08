#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/forensics

    cat << 'EOF' > /home/user/forensics/generate_dump.py
import struct
import random

c2 = "http://evil-c2-server.internal/api/v1/beacon"
encoded_floats = [str(ord(c) * 0.3) for c in c2]
payload = "C2_OBF_START{" + ",".join(encoded_floats) + "}"

with open("/home/user/forensics/memdump.raw", "wb") as f:
    # write some random garbage bytes
    f.write(bytearray(random.getrandbits(8) for _ in range(1024)))
    # write the payload
    f.write(payload.encode('utf-8'))
    # write more garbage
    f.write(bytearray(random.getrandbits(8) for _ in range(1024)))
EOF
    python3 /home/user/forensics/generate_dump.py
    rm /home/user/forensics/generate_dump.py

    cat << 'EOF' > /home/user/forensics/decode.py
import sys

def decode_payload(encoded_str):
    # Remove wrappers if present
    if encoded_str.startswith("C2_OBF_START{"):
        encoded_str = encoded_str[13:-1]

    parts = encoded_str.split(",")
    decoded = ""
    for p in parts:
        if not p.strip(): continue
        val = float(p)
        # Bug: precision loss during division and truncation
        # e.g., 33.6 / 0.3 = 111.99999999999999, int() truncates to 111 ('o' instead of 'p')
        char_code = int(val / 0.3)
        decoded += chr(char_code)
    return decoded

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 decode.py <encoded_string>")
        sys.exit(1)

    result = decode_payload(sys.argv[1])
    print("Decoded URL:", result)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

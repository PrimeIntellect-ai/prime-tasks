#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/forensics

    cat << 'EOF' > /tmp/setup.py
import os

forensics_dir = "/home/user/forensics"
os.makedirs(forensics_dir, exist_ok=True)
dat_file_path = os.path.join(forensics_dir, "exfiltrated.dat")

plaintext = """EVIDENCE_START
Host: web-server-01
Timestamp: 2023-10-24T08:15:32Z
Action: database_dump
Dump contents:
User: alice | Card: 4532-1111-2222-3333 | Exp: 12/25
User: bob | Card: 5412-9999-8888-7777 | Exp: 01/26
User: charlie | Card: 3759-1234-5678-9012 | Exp: 08/24
Notes: Ensure logs are cleared after extraction.
END_OF_DUMP"""

xor_key = 0x47
encrypted_data = bytearray(ord(c) ^ xor_key for c in plaintext)

with open(dat_file_path, 'wb') as f:
    f.write(encrypted_data)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

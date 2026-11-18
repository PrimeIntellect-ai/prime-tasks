#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    mkdir -p /home/user/forensics
    mkdir -p /home/user/system_backup/app_data/tmp

    cat << 'EOF' > /tmp/setup_env.py
import os
import json
import hashlib
from cryptography.fernet import Fernet

key = Fernet.generate_key()
backup_file_path = '/home/user/system_backup/app_data/tmp/.key_backup'
os.makedirs(os.path.dirname(backup_file_path), exist_ok=True)
with open(backup_file_path, 'wb') as f:
    f.write(key)
os.chmod(backup_file_path, 0o644)

flag_value = "CTF{f0r3ns1cs_r3c0v3ry_m4st3r_8832}"
evidence_data = {
    "id": 992,
    "secret_evidence": flag_value,
    "timestamp": "2023-10-25T14:32:00Z"
}

cipher = Fernet(key)
encrypted_evidence = cipher.encrypt(json.dumps(evidence_data).encode('utf-8'))

with open('/home/user/forensics/evidence.enc', 'wb') as f:
    f.write(encrypted_evidence)

sha256_hash = hashlib.sha256(flag_value.encode('utf-8')).hexdigest()
with open('/home/user/forensics/checksum.txt', 'w') as f:
    f.write(sha256_hash)
EOF

    python3 /tmp/setup_env.py
    rm /tmp/setup_env.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

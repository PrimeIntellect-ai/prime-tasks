#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create setup script
    cat << 'EOF' > /tmp/setup.py
import os
import json
import struct
import subprocess

# Create evidence directory
os.makedirs('/home/user/evidence', exist_ok=True)

# --- 1. Generate auth_logs.json ---
logs = []
# Normal user
for i in range(5):
    logs.append({"timestamp": 1600000000 + i*10, "ip": "10.0.0.5", "username": "alice", "status": "failed"})
logs.append({"timestamp": 1600000050, "ip": "10.0.0.5", "username": "alice", "status": "success"})

# Attacker IP: 192.168.1.100 (15 fails in 60s, then success)
start_time = 1600001000
for i in range(15):
    logs.append({"timestamp": start_time + i*3, "ip": "192.168.1.100", "username": "admin", "status": "failed"})
logs.append({"timestamp": start_time + 48, "ip": "192.168.1.100", "username": "admin", "status": "success"})

# Another noisy IP but no success
for i in range(20):
    logs.append({"timestamp": 1600002000 + i*2, "ip": "172.16.5.5", "username": "root", "status": "failed"})

with open('/home/user/evidence/auth_logs.json', 'w') as f:
    for log in logs:
        f.write(json.dumps(log) + '\n')

# --- 2. Generate suspicious.elf ---
# Create a dummy C program, compile it, and inject a custom section
c_code = """
int main() {
    return 0;
}
"""
with open('/tmp/dummy.c', 'w') as f:
    f.write(c_code)

subprocess.run(['gcc', '/tmp/dummy.c', '-o', '/home/user/evidence/suspicious.elf'], check=True)

# Key is 0xDE 0xAD 0xBE 0xEF 0x12 0x34 0x56 0x78
key = bytes([0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34, 0x56, 0x78])
with open('/tmp/malconf.bin', 'wb') as f:
    f.write(key)

subprocess.run(['objcopy', '--add-section', '.malconf=/tmp/malconf.bin', '/home/user/evidence/suspicious.elf'], check=True)

# --- 3. Generate payload.bin ---
flag = b"FLAG{3lf_x0r_f0r3ns1cs_99}"
encrypted_payload = bytearray()
for i in range(len(flag)):
    encrypted_payload.append(flag[i] ^ key[i % len(key)])

with open('/home/user/evidence/payload.bin', 'wb') as f:
    f.write(encrypted_payload)

# Clean up
os.remove('/tmp/dummy.c')
os.remove('/tmp/malconf.bin')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

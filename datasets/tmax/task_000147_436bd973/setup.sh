#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import base64

# 1. Create a dummy ELF binary containing the C2_SERVER string
elf_header = b'\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
elf_body = b'\x02\x00\x3e\x00\x01\x00\x00\x00\x10\x11\x40\x00\x00\x00\x00\x00'
dummy_elf = elf_header + elf_body + b'somejunkdata\x00C2_SERVER=https://10.99.88.77/c2/register\x00morejunk'

# 2. Encrypt with XOR key 137 (0x89)
xor_key = 137
encrypted_elf = bytes([b ^ xor_key for b in dummy_elf])
b64_payload = base64.b64encode(encrypted_elf).decode('utf-8')

# 3. Create the SQLi payload
sqli_payload = f"SELECT * FROM users WHERE id=1 UNION SELECT 1, '{b64_payload}' --"

# 4. Create the malicious JWT (alg=none)
malicious_jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJyb2xlIjoiYWRtaW4ifQ."

# 5. Create traffic log
traffic_log = [
    {
        "timestamp": "2023-10-24T10:00:00Z",
        "method": "GET",
        "headers": {"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidXNlciJ9.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"},
        "data": "user=test"
    },
    {
        "timestamp": "2023-10-24T10:05:12Z",
        "method": "POST",
        "headers": {"Authorization": f"Bearer {malicious_jwt}"},
        "data": sqli_payload
    },
    {
        "timestamp": "2023-10-24T10:06:00Z",
        "method": "POST",
        "headers": {"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiZ3Vlc3QifQ.wrong_sig"},
        "data": "action=ping"
    }
]

with open('/home/user/traffic_capture.json', 'w') as f:
    json.dump(traffic_log, f, indent=2)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

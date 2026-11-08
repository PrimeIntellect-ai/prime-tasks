#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_payloads.py
import binascii

plaintexts = [
    "CMD:SCAN|TARGET_IP:10.0.0.5|USER:root|PASS:toor|ACTION:PING",
    "CMD:EXEC|TARGET_IP:172.16.1.10|USER:admin|PASS:P@ssw0rd1|ACTION:DROP",
    "CMD:LATERAL|TARGET_IP:192.168.100.45|USER:svc_account|PASS:M%4K9!xZ|ACTION:WMI"
]

key = 0x2B

with open('/home/user/intercepted_payloads.txt', 'w') as f:
    for pt in plaintexts:
        xored = bytes([ord(c) ^ key for c in pt])
        hex_encoded = binascii.hexlify(xored).decode('utf-8').upper()
        f.write(hex_encoded + '\n')
EOF

    python3 /home/user/setup_payloads.py
    rm /home/user/setup_payloads.py

    chmod -R 777 /home/user

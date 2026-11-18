#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/service-config
    cd /home/user/service-config
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"
    echo '{"app_name": "reporting_service", "api_token": "SUPER_SECRET_TOKEN_9942", "port": 8080}' > config.json
    git add config.json
    git commit -m "Initial commit with config"
    echo '{"app_name": "reporting_service", "api_token": "REDACTED", "port": 8080}' > config.json
    git add config.json
    git commit -m "Fix: removed hardcoded token"
    cd /home/user

    cat << 'EOF' > /home/user/service.log
[2023-10-25 14:05:22] 10.0.0.5 AUTH_SUCCESS Token=VALID_TOKEN_111
[2023-10-25 14:12:00] 192.168.55.123 AUTH_FAILED Token=INVALID_123
[2023-10-25 14:32:01] 192.168.55.123 AUTH_SUCCESS Token=SUPER_SECRET_TOKEN_9942
[2023-10-25 14:35:10] 10.0.0.6 AUTH_SUCCESS Token=VALID_TOKEN_222
EOF

    cat << 'EOF' > /home/user/generate_pcap.py
import struct

def write_pcap(filename):
    with open(filename, 'wb') as f:
        # Global header
        f.write(struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))

        # Craft a dummy IPv4 packet
        # Attacker IP: 192.168.55.123 -> c0 a8 37 7b
        # Dest IP: 10.0.0.1 -> 0a 00 00 01
        payload = b"GET /admin HTTP/1.1\r\nHeader: UNAUTHORIZED_ACCESS\r\n\r\n"

        # IP Header (20 bytes)
        ip_header = b'\x45\x00\x00' + bytes([20 + len(payload)]) + b'\x00\x00\x40\x00\x40\x11\x00\x00\xc0\xa8\x37\x7b\x0a\x00\x00\x01'

        packet = ip_header + payload

        # Packet header
        ts_sec = 1698244321
        ts_usec = 0
        incl_len = len(packet)
        orig_len = len(packet)
        f.write(struct.pack('<IIII', ts_sec, ts_usec, incl_len, orig_len))
        f.write(packet)

write_pcap('/home/user/capture.pcap')
EOF

    python3 /home/user/generate_pcap.py
    rm /home/user/generate_pcap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

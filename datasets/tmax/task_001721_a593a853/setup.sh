#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/generate_data.py
import csv

with open('/home/user/server_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'server_id', 'latency_ms', 'status'])

    # SRV-001: 14 FAILs, 86 OKs
    for i in range(14):
        writer.writerow([f'2023-10-01T00:{i:02d}:00', 'SRV-001', 1200, 'FAIL'])
    for i in range(14, 100):
        writer.writerow([f'2023-10-01T00:{i:02d}:00', 'SRV-001', 150, 'OK'])

    # SRV-002: Noise data
    for i in range(50):
        writer.writerow([f'2023-10-01T01:{i:02d}:00', 'SRV-002', 500, 'FAIL'])
EOF

python3 /home/user/generate_data.py
rm /home/user/generate_data.py

chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv

with open('/home/user/system_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'level', 'component', 'message'])

    # Bucket 1: 10:00
    writer.writerow(['2023-10-01T10:01:00Z', 'INFO', 'auth', 'Login success'])
    writer.writerow(['2023-10-01T10:02:15Z', 'ERROR', 'db', 'Connection timeout\nRetrying...'])
    writer.writerow(['2023-10-01T10:04:59Z', 'ERROR', 'api', 'Null pointer exception\nLine 42'])

    # Bucket 2: 10:05
    writer.writerow(['2023-10-01T10:06:00Z', 'INFO', 'web', 'Page load\nUser profile'])

    # Bucket 3: 10:10
    writer.writerow(['2023-10-01T10:11:00Z', 'ERROR', 'db', 'Deadlock found\nTransaction aborted'])
    writer.writerow(['2023-10-01T10:12:00Z', 'ERROR', 'db', 'Connection lost'])
    writer.writerow(['2023-10-01T10:13:00Z', 'ERROR', 'auth', 'Invalid token\nVerify key'])
    writer.writerow(['2023-10-01T10:14:00Z', 'ERROR', 'auth', 'Token expired'])

    # Bucket 4: 10:15 (No logs at all)

    # Bucket 5: 10:20
    writer.writerow(['2023-10-01T10:21:00Z', 'ERROR', 'api', 'Rate limit exceeded'])
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

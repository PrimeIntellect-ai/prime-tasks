#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv

with open('/home/user/metrics.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'server_id', 'temperature', 'cpu_load', 'status_msg'])

    # Valid row 1: Earliest for S1 on 2023-10-01
    writer.writerow(['2023-10-01T08:15:00Z', 'S1', '45.2', '60.0', 'System OK!'])
    # Valid row 2: Later for S1 on 2023-10-01 (should be dropped)
    writer.writerow(['2023-10-01T14:20:00Z', 'S1', '46.1', '65.0', 'System Still OK'])

    # Invalid row: temp too high
    writer.writerow(['2023-10-01T07:10:00Z', 'S2', '125.0', '90.0', 'FIRE!!'])
    # Valid row: Earliest valid for S2 on 2023-10-01
    writer.writerow(['2023-10-01T09:00:00Z', 'S2', '80.5', '95.0', 'Warning: High Load...'])

    # Invalid row: negative cpu load
    writer.writerow(['2023-10-02T10:00:00Z', 'S1', '40.0', '-5.0', 'sensor error'])

    # Valid row: Earliest for S1 on 2023-10-02
    writer.writerow(['2023-10-02T11:00:00Z', 'S1', '42.0', '50.0', '  ALL   GOOD! 123 '])

    # Valid row: Earliest for S3 on 2023-10-02
    writer.writerow(['2023-10-02T01:00:00Z', 'S3', '35.0', '10.0', 'Idle @ night'])
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random
import os

os.makedirs('/home/user', exist_ok=True)
random.seed(12345)

with open('/home/user/perf_logs.csv', 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'endpoint', 'latency_ms', 'payload_size'])
    for i in range(20000):
        endpoint = random.choice(['/api/v1/process', '/api/v1/status', '/api/v1/query'])
        payload_size = random.randint(10, 1000)

        if endpoint == '/api/v1/process':
            if payload_size <= 100:
                lat = random.expovariate(1/50.0)
            elif payload_size <= 500:
                lat = random.expovariate(1/150.0)
            else:
                lat = random.expovariate(1/400.0)
        else:
            lat = random.expovariate(1/25.0)

        writer.writerow([i, endpoint, round(lat, 2), payload_size])
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

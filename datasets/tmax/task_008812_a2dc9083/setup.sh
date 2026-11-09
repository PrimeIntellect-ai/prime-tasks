#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_logs.py
import csv
import random

random.seed(42)

def generate_logs(filename):
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)

        # Start time
        current_time = 1000000

        for window in range(100):
            window_start = current_time + (window * 10)

            # Normal traffic (5-15 requests per 10s window)
            num_requests = random.randint(5, 15)

            # Anomalies
            if window == 20:
                num_requests = 100 # Spike 1
            elif window == 50:
                num_requests = 150 # Spike 2

            ips_for_window = []
            if window == 20:
                ips_for_window = [f"192.168.1.{i}" for i in range(1, 11)] * 10
            elif window == 50:
                ips_for_window = ["10.0.0.5", "10.0.0.99"] * 75
            else:
                ips_for_window = [f"172.16.0.{random.randint(1,5)}" for _ in range(num_requests)]

            for i in range(num_requests):
                t = window_start + random.randint(0, 9)
                ip = ips_for_window[i]
                endpoint = "/api/v1/data"
                status = 200
                ms = random.randint(10, 100)
                writer.writerow([t, ip, endpoint, status, ms])

generate_logs('/home/user/server_logs.csv')
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user

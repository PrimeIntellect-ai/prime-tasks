#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas dask

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random
import csv

os.makedirs('/home/user/telemetry_data', exist_ok=True)
random.seed(42)

servers = ['  alpha-1', 'BETA-2  ', 'gamma-3', ' alpha-1 ', 'beta-2']

for i in range(1, 51):
    filepath = f'/home/user/telemetry_data/telemetry_{i:02d}.csv'
    with open(filepath, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'server_id', 'cpu_node1', 'mem_node1', 'cpu_node2', 'mem_node2'])
        rows = []
        for j in range(100):
            ts = f"2023-10-01T12:{j:02d}:00"
            srv = random.choice(servers)

            c1 = round(random.uniform(10.0, 90.0), 2) if random.random() > 0.1 else ""
            m1 = round(random.uniform(1000, 8000), 2) if random.random() > 0.1 else "NaN"
            c2 = round(random.uniform(10.0, 90.0), 2) if random.random() > 0.1 else ""
            m2 = round(random.uniform(1000, 8000), 2) if random.random() > 0.1 else ""

            # Create all missing case
            if random.random() < 0.05:
                c1, m1, c2, m2 = "", "NaN", "", ""

            rows.append([ts, srv, c1, m1, c2, m2])

            # Inject duplicates
            if random.random() < 0.1:
                rows.append([ts, srv, c1, m1, c2, m2])

        writer.writerows(rows)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

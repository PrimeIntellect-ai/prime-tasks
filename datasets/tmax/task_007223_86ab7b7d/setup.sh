#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import os
import math
import csv

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/reference_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['x', 'y', 'temperature'])
    for i in range(1, 20):
        for j in range(1, 20):
            x = i / 20.0
            y = j / 20.0
            # Analytical solution with slight artificial noise
            val = (math.sinh(math.pi * (1 - y)) / math.sinh(math.pi)) * math.sin(math.pi * x)
            val += 0.01 * math.sin(x*y) # deterministic noise
            writer.writerow([x, y, val])
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user

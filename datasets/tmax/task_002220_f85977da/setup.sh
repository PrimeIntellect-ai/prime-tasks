#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import csv
import random

random.seed(42)

data = []
# Create REF_001
data.append({'ID': 'REF_001', 'Feature_A': 100, 'Feature_B': 500, 'Feature_C': 200, 'Target': 1})

# Generate 99 other rows
for i in range(2, 101):
    fa = random.randint(10, 200)
    fb = random.randint(100, 1000)
    fc = random.randint(50, 400)
    # create some correlation
    target = 1 if (fa + fc) > 300 else 0
    data.append({'ID': f'ROW_{i:03d}', 'Feature_A': fa, 'Feature_B': fb, 'Feature_C': fc, 'Target': target})

# Write to CSV
with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['ID', 'Feature_A', 'Feature_B', 'Feature_C', 'Target'])
    writer.writeheader()
    writer.writerows(data)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import random

os.makedirs('/home/user/data', exist_ok=True)
os.makedirs('/home/user/results', exist_ok=True)

random.seed(10)
num_machines = 500

# Generate sensors.csv
with open('/home/user/data/sensors.csv', 'w') as f:
    f.write("machine_id,temperature,vibration\n")
    for i in range(num_machines):
        m_id = f"M_{i:03d}"
        if random.random() < 0.2:
            temp = ""
        else:
            temp = round(random.uniform(20.0, 80.0), 1)
        vib = round(random.uniform(0.1, 5.0), 2)
        f.write(f"{m_id},{temp},{vib}\n")

# Generate maintenance.json
maintenance_data = []
random.seed(20)
for i in range(num_machines):
    m_id = f"M_{i:03d}"
    needs_repair = 1 if random.random() < 0.3 else 0
    maintenance_data.append({"machine_id": m_id, "needs_repair": needs_repair})

with open('/home/user/data/maintenance.json', 'w') as f:
    json.dump(maintenance_data, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

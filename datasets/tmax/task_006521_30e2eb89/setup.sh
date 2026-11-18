#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/setup_data.py
import csv
import random

random.seed(42)

normal_templates = [
    "User {} logged in successfully from IP 192.168.1.{}",
    "Connection to database established in {} ms",
    "Session {} timeout after 30 minutes of inactivity",
    "Request payload validation passed for endpoint /api/v1/resource",
    "Background job {} completed with status OK"
]

anomalous_messages = [
    "FATAL ERROR: Buffer overflow detected in module xyz at memory address 0x00000000",
    "WARNING: Multiple failed authentication attempts (500+) from unknown IP",
    "CRITICAL: Data corruption found in cluster node 7, initiating emergency shutdown",
    "Unexpected payload format: executing shell injection payload ; rm -rf /",
    "System configuration file /etc/passwd modified by unauthorized user"
]

data = []
for i in range(45):
    template = random.choice(normal_templates)
    if "{}" in template:
        if "IP" in template:
            msg = template.format(random.randint(1000, 9999), random.randint(10, 255))
        elif "ms" in template:
            msg = template.format(random.randint(5, 50))
        else:
            msg = template.format(random.randint(10000, 99999))
    else:
        msg = template
    data.append([msg])

for msg in anomalous_messages:
    data.append([msg])

random.shuffle(data)

with open("/home/user/data/logs.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["message"])
    writer.writerows(data)
EOF

    python3 /home/user/data/setup_data.py

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest pandas scikit-learn scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user/data', exist_ok=True)

# Generate synthetic log data
random.seed(42)
messages = [
    "Connection timeout reached for process ID",
    "Successfully authenticated user",
    "Disk space critically low on mount",
    "Invalid payload received from endpoint",
    "Database query executed successfully in ms",
    "Out of memory error allocating bytes",
    "Health check passed",
    "Unrecognized command syntax",
    "Network interface eth0 down",
    "Cache hit for key"
]

with open('/home/user/data/logs.csv', 'w') as f:
    f.write("id,response_time,message,is_anomaly\n")
    for i in range(1, 501):
        msg = random.choice(messages)

        # Introduce anomalies based on certain messages
        is_anomaly = 1 if "error" in msg.lower() or "timeout" in msg.lower() or "critical" in msg.lower() else 0

        # Response time logic
        if is_anomaly:
            rt = random.uniform(800, 6000) # Some > 5000 (outliers)
        else:
            rt = random.uniform(10, 400)

        # Introduce missing values and negative outliers
        rand_val = random.random()
        if rand_val < 0.05:
            rt_str = "NA"
        elif rand_val < 0.10:
            rt_str = str(round(-random.uniform(10, 100), 2))
        else:
            rt_str = str(round(rt, 2))

        # Add a random id to message to increase vocabulary variance slightly
        full_msg = f"{msg} {random.randint(1000,9999)}"
        f.write(f"{i},{rt_str},{full_msg},{is_anomaly}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

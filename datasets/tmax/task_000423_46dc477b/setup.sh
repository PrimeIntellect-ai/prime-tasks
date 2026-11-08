#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/create_data.py
import random

random.seed(123)
with open('/home/user/sensor_data.csv', 'w') as f:
    f.write("timestamp,sensor_id,temperature,status\n")
    for i in range(1000):
        ts = 1600000000 + i * 60
        sid = f"S{random.randint(1, 5)}"
        if random.random() < 0.05:
            temp = ""
        elif random.random() < 0.05:
            temp = "NA"
        else:
            temp = round(random.gauss(25.0, 2.0), 2)
        status = "ok" if random.random() < 0.9 else "error"
        f.write(f"{ts},{sid},{temp},{status}\n")
EOF
    python3 /home/user/create_data.py
    rm /home/user/create_data.py

    chmod -R 777 /home/user

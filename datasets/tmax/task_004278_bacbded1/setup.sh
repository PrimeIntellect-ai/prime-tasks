#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_archive
    cd /home/user/log_archive

    cat << 'EOF' > generate_logs.py
import random
from datetime import datetime, timedelta

start_time = datetime(2023, 10, 27, 14, 0, 0)
anomaly_time = datetime(2023, 10, 27, 14, 35, 0) # The anomaly starts here

for file_idx in range(4):
    filename = f"server_{file_idx}.log"
    with open(filename, 'w', encoding='utf-16le') as f:
        current_time = start_time
        while current_time < datetime(2023, 10, 27, 15, 0, 0):
            ip = f"10.0.0.{random.randint(1, 255)}"
            status = 200

            if current_time >= anomaly_time:
                rt = random.randint(600, 950) # Anomaly response time
            else:
                rt = random.randint(50, 250)  # Normal response time

            line = f"{current_time.strftime('%Y-%m-%d %H:%M:%S')}|{ip}|{status}|{rt}\n"
            f.write(line)
            current_time += timedelta(seconds=random.randint(5, 15))
EOF

    python3 generate_logs.py
    rm generate_logs.py

    chmod -R 777 /home/user

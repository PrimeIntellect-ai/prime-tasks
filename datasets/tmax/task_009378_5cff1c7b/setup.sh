#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import random

random.seed(123)

with open('/home/user/service_A_logs.csv', 'w') as fa, open('/home/user/service_B_logs.csv', 'w') as fb:
    fa.write("req_id,latency_ms\n")
    fb.write("req_id,latency_ms\n")

    # 1000 total potential req_ids
    for req_id in range(1, 1001):
        in_a = random.random() < 0.8
        in_b = random.random() < 0.8

        lat_a = round(random.uniform(10.0, 50.0), 2)
        lat_b = round(random.uniform(5.0, 20.0), 2)

        if in_a:
            fa.write(f"{req_id},{lat_a}\n")
        if in_b:
            fb.write(f"{req_id},{lat_b}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

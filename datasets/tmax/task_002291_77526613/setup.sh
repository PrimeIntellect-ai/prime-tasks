#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_task.py
import csv
import random

# True parameters
true_a = 0.5
true_b = 2.0
true_c = 1.5

random.seed(42)

with open('/home/user/profiling_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['N', 'C', 'Time', 'Status'])

    for N in [1000, 5000, 10000, 20000, 30000]:
        for C in [1, 2, 4, 8, 16, 32]:
            # Exact time
            T = true_a * (N / C) + true_b * (C ** true_c)

            # Add small noise
            noise = random.uniform(-0.01, 0.01) * T
            T_noisy = T + noise

            # 15% chance of timeout (corrupted data)
            if random.random() < 0.15:
                writer.writerow([N, C, T_noisy * 5.0, 'Timeout'])
            else:
                writer.writerow([N, C, T_noisy, 'Success'])
EOF
    python3 /tmp/setup_task.py

    chmod -R 777 /home/user

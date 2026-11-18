#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import math

W_lin = [0.5, 1.5, -0.5]
B_lin = 1.0
W_log = [-1.0, 0.5, 2.0]
B_log = -0.5

linear_sum = 0.0
logistic_pos = 0

with open('/home/user/data.csv', 'w') as f:
    for i in range(10000):
        x0 = (i % 100) * 0.05
        x1 = (i % 50) * 0.1
        x2 = (i % 25) * 0.2

        f.write(f"{x0:.2f},{x1:.2f},{x2:.2f}\n")

        y = W_lin[0]*x0 + W_lin[1]*x1 + W_lin[2]*x2 + B_lin
        linear_sum += y

        z = W_log[0]*x0 + W_log[1]*x1 + W_log[2]*x2 + B_log
        p = 1.0 / (1.0 + math.exp(-z))
        if p >= 0.5:
            logistic_pos += 1

with open('/tmp/expected_sum.txt', 'w') as f:
    f.write(f"{linear_sum:.2f}")

with open('/tmp/expected_count.txt', 'w') as f:
    f.write(str(logistic_pos))
EOF

    python3 /tmp/generate_data.py

    chmod -R 777 /home/user

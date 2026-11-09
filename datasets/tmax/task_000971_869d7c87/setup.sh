#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user/data', exist_ok=True)

# Model parameters
w_a = 1.5
w_b = -0.5
bias = 2.0

with open('/home/user/model_params.txt', 'w') as f:
    f.write(f"weight_A={w_a}\nweight_B={w_b}\nbias={bias}\n")

random.seed(42)

def generate_csv(filename, num_rows):
    with open(filename, 'w') as f:
        f.write("sensor_A,sensor_B,actual_output\n")
        for _ in range(num_rows):
            a = random.uniform(0.0, 10.0)
            b = random.uniform(0.0, 10.0)
            pred = w_a * a + w_b * b + bias
            # Add some noise
            noise = random.gauss(0, 1.0)
            actual = pred + noise
            f.write(f"{a:.4f},{b:.4f},{actual:.4f}\n")

generate_csv('/home/user/data/sensor_batch_1.csv', 100)
generate_csv('/home/user/data/sensor_batch_2.csv', 150)
generate_csv('/home/user/data/sensor_batch_3.csv', 50)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user

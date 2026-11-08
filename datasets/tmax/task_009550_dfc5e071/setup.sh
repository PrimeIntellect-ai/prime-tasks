#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc gawk coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user
cd /home/user

cat << 'EOF' > generate_data.py
import random
import math

random.seed(42)
with open("dataset.tsv", "w") as f:
    for i in range(10000):
        # Generate correlated variables
        base = random.gauss(0, 1)
        noise_a = random.gauss(0, 0.5)
        noise_b = random.gauss(0, 0.5)

        sensor_a = base * 1.5 + noise_a + 10.0
        sensor_b = base * 2.0 + noise_b - 5.0

        timestamp = 1600000000 + i * 10

        f.write(f"{i}\t{sensor_a:.6f}\t{timestamp}\t{sensor_b:.6f}\n")
EOF
python3 generate_data.py
rm generate_data.py

chmod -R 777 /home/user

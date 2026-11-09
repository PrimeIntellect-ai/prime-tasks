#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++ cmake make
    pip3 install pytest

    # Clone the CSV parser and perturb the CMakeLists.txt
    mkdir -p /app
    git clone --branch 2.1.3 https://github.com/vincentlaucsb/csv-parser.git /app/csv-parser
    sed -i 's/set(CMAKE_CXX_STANDARD 17)/set(CMAKE_CXX_STANDARD 11)/g' /app/csv-parser/CMakeLists.txt

    # Generate CSV data
    cat << 'EOF' > /tmp/generate_data.py
import os
import random

os.makedirs('/app/data/clean', exist_ok=True)
os.makedirs('/app/data/evil', exist_ok=True)

def generate_csv(path, n_rows, f1_target, f2_target, f3_target):
    with open(path, 'w') as f:
        f.write('timestamp,sensor_x,sensor_y,sensor_z\n')
        for i in range(n_rows):
            # f1 is mean of sensor_x
            sx = f1_target + random.uniform(-0.1, 0.1)
            # f2 is max abs of sensor_y. We can just set all to f2_target or close to it
            sy = f2_target if i == 0 else random.uniform(0, f2_target)
            if random.choice([True, False]): sy = -sy
            # f3 is rms of sensor_z. We can set all to f3_target
            sz = f3_target + random.uniform(-0.01, 0.01)
            f.write(f"{i},{sx},{sy},{sz}\n")

for i in range(50):
    generate_csv(f'/app/data/clean/clean_{i}.csv', 100, 0.0, 0.5, 0.5)
    generate_csv(f'/app/data/evil/evil_{i}.csv', 100, 5.0, 0.1, 0.1)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

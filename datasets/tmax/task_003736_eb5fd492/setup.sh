#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import random
import csv

random.seed(42)

ids = list(range(1, 101))
random.shuffle(ids)

data_x = []
data_y = []

# Y = 2.5 * X + 1.0 + noise
for i in ids:
    x = random.uniform(0, 10)
    # 85% normal data, 15% outliers
    if random.random() > 0.15:
        noise = random.gauss(0, 0.5)
    else:
        noise = random.gauss(0, 5.0) # outliers

    y = 2.5 * x + 1.0 + noise
    data_x.append((i, round(x, 4)))
    data_y.append((i, round(y, 4)))

# Shuffle the final lists to ensure they are out of order
random.shuffle(data_x)
random.shuffle(data_y)

with open('data_X.csv', 'w') as f:
    f.write("ID,X\n")
    for row in data_x:
        f.write(f"{row[0]},{row[1]:.4f}\n")

with open('data_Y.csv', 'w') as f:
    f.write("ID,Y\n")
    for row in data_y:
        f.write(f"{row[0]},{row[1]:.4f}\n")
EOF

    python3 generate_data.py
    rm generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake nlohmann-json3-dev
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import csv
import random

random.seed(42)

# Generate 1000 points
# We want a cluster around 0.3, 0.3 and another around 0.7, 0.7
points = []
for _ in range(600):
    x = random.gauss(0.3, 0.1)
    y = random.gauss(0.3, 0.1)
    points.append((x, y))

for _ in range(400):
    x = random.gauss(0.7, 0.15)
    y = random.gauss(0.7, 0.15)
    points.append((x, y))

# Filter points to be strictly within [0,1]x[0,1]
filtered_points = []
for x, y in points:
    if 0 <= x <= 1 and 0 <= y <= 1:
        filtered_points.append((x, y))

# Fill up to exactly 1000 valid points
while len(filtered_points) < 1000:
    x = random.gauss(0.5, 0.3)
    y = random.gauss(0.5, 0.3)
    if 0 <= x <= 1 and 0 <= y <= 1:
        filtered_points.append((x, y))

with open('/home/user/spatial_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    for p in filtered_points:
        writer.writerow([round(p[0], 5), round(p[1], 5)])
EOF

    python3 generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

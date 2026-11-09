#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import csv

c = 0.45
m = 10.0
g = 9.81
dt = 0.01
y = 1000.0
v = 0.0

data = []

# Simulate for 10 seconds (1000 steps)
for steps in range(1001):
    t = steps * dt
    # Save data every 1 second (100 steps)
    if steps % 100 == 0:
        data.append((round(t, 2), round(y, 4)))

    # Forward Euler step
    a = -g - (c/m) * v * abs(v)
    y_new = y + v * dt
    v_new = v + a * dt
    y = y_new
    v = v_new

file_path = '/home/user/trajectory_data.csv'
with open(file_path, 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['time', 'height'])
    for row in data:
        writer.writerow(row)
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

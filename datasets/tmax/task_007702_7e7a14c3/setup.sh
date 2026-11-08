#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup.py
import csv
import math

dt = 0.1
t_max = 10.0

with open('/home/user/raw_sensor.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['t', 'a'])
    t = 0.0
    while t <= t_max + 1e-9:
        a = math.sin(t)
        writer.writerow([round(t, 2), a])
        t += dt

with open('/home/user/reference_trajectory.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['t', 'v_ref', 'p_ref'])
    t = 0.0
    while t <= 2.0 + 1e-9:
        v = 1 - math.cos(t)
        p = t - math.sin(t)
        writer.writerow([round(t, 2), v, p])
        t += dt
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user

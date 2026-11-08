#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg curl
    pip3 install pytest

    mkdir -p /app/data
    cd /app/data

    # Create a synthetic video (10 frames, 1 fps for simplicity, changing colors)
    ffmpeg -f lavfi -i "color=c=red:s=64x64:d=3" -f lavfi -i "color=c=green:s=64x64:d=3" -f lavfi -i "color=c=blue:s=64x64:d=4" -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0" -r 1 experiment.mp4

    # Create sensor_a.csv and sensor_b.csv
    cat << 'EOF' > make_csv.py
import csv
import random

random.seed(42)
with open('sensor_a.csv', 'w', newline='') as fa, open('sensor_b.csv', 'w', newline='') as fb:
    wa = csv.writer(fa)
    wb = csv.writer(fb)

    header_a = ['frame_id'] + [f'sa_{i}' for i in range(1, 11)]
    header_b = ['frame_id'] + [f'sb_{i}' for i in range(1, 11)]
    wa.writerow(header_a)
    wb.writerow(header_b)

    for i in range(10):
        row_a = [i] + [random.random() for _ in range(10)]
        row_b = [i] + [random.random() for _ in range(10)]
        wa.writerow(row_a)
        wb.writerow(row_b)
EOF
    python3 make_csv.py
    rm make_csv.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

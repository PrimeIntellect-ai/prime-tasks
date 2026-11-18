#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg imagemagick gawk
pip3 install pytest Pillow

mkdir -p /app

cat << 'EOF' > /tmp/generate_data.py
import os
import csv
import random
from PIL import Image
import subprocess

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)
os.makedirs('/app/hidden_corpus/clean', exist_ok=True)
os.makedirs('/app/hidden_corpus/evil', exist_ok=True)

# Generate video frames
os.makedirs('/tmp/frames', exist_ok=True)
anomalies = [2.3, 5.6, 5.7, 8.1]
anomaly_frames = [int(round(t * 10)) for t in anomalies]

for i in range(100):
    img = Image.new('RGB', (100, 100), color='black')
    if i in anomaly_frames:
        for x in range(10):
            for y in range(10):
                img.putpixel((x, y), (255, 0, 0))
    img.save(f'/tmp/frames/frame_{i:03d}.png')

subprocess.run(['ffmpeg', '-y', '-framerate', '10', '-i', '/tmp/frames/frame_%03d.png', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/machine_feed.mp4'], check=True)

# Generate training log
with open('/app/training_log.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp','sensor_alpha','sensor_beta','sensor_gamma'])
    for i in range(100):
        t = i / 10.0
        alpha = random.randint(35, 45)
        gamma = random.randint(780, 820)
        if i in anomaly_frames:
            beta = random.randint(151, 180)
        else:
            beta = random.randint(50, 149)
        writer.writerow([f"{t:.1f}", alpha, beta, gamma])

# Generate corpus
def generate_corpus(path, is_evil, num_files=20):
    for f_idx in range(num_files):
        with open(f'{path}/log_{f_idx}.csv', 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp','sensor_alpha','sensor_beta','sensor_gamma'])
            evil_row = random.randint(0, 99) if is_evil else -1
            for i in range(100):
                t = i / 10.0
                alpha = random.randint(35, 45)
                gamma = random.randint(780, 820)
                if i == evil_row:
                    beta = random.randint(151, 180)
                else:
                    beta = random.randint(50, 149)
                writer.writerow([f"{t:.1f}", alpha, beta, gamma])

generate_corpus('/app/corpus/clean', False, 20)
generate_corpus('/app/corpus/evil', True, 20)
generate_corpus('/app/hidden_corpus/clean', False, 20)
generate_corpus('/app/hidden_corpus/evil', True, 20)
EOF

python3 /tmp/generate_data.py
rm -rf /tmp/frames /tmp/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app

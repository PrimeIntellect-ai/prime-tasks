#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sudo gcc
pip3 install pytest

useradd -m -s /bin/bash user || true
echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

mkdir -p /home/user/data

cat << 'EOF' > /home/user/data/generate.py
import csv
import random

random.seed(42)
w0, w1, w2 = 1.5, -2.0, 0.5

with open('/home/user/data/weights.txt', 'w') as f:
    f.write(f"{w0}\n{w1}\n{w2}\n")

features = []
labels = []

for i in range(1, 101):
    x1 = random.uniform(0, 10)
    x2 = random.uniform(0, 10)
    features.append([i, round(x1, 3), round(x2, 3)])

    # y = w0 + w1*x1 + w2*x2 + noise
    y_true = w0 + w1*x1 + w2*x2

    # Add large noise to some to make them outliers
    if i % 7 == 0:
        noise = random.uniform(3.0, 5.0) * random.choice([-1, 1])
    else:
        noise = random.uniform(-0.5, 0.5)

    y = y_true + noise
    labels.append([i, round(y, 3)])

# Shuffle labels to ensure ID matching is actually required
random.shuffle(labels)

with open('/home/user/data/features.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(features)

with open('/home/user/data/labels.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(labels)
EOF

python3 /home/user/data/generate.py

chmod -R 777 /home/user

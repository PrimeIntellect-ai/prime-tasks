#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

# Create user
useradd -m -s /bin/bash user || true

# Generate raw_data.bin and expected files
cat << 'EOF' > /tmp/setup.py
import struct
import random
import os

os.makedirs('/home/user', exist_ok=True)

random.seed(42)
floats = [random.uniform(-10.0, 10.0) for _ in range(4000)]

with open('/home/user/raw_data.bin', 'wb') as f:
    f.write(struct.pack(f'{len(floats)}f', *floats))

global_mean = sum(floats) / len(floats)
with open('/home/user/expected_global_mean.txt', 'w') as f:
    f.write(f"{global_mean:.4f}\n")

cleaned = []
for i in range(0, 4000, 4):
    vec = floats[i:i+4]
    v_mean = sum(vec) / 4.0
    cleaned.extend([x - v_mean for x in vec])

with open('/home/user/expected_cleaned_data.bin', 'wb') as f:
    f.write(struct.pack(f'{len(cleaned)}f', *cleaned))
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user

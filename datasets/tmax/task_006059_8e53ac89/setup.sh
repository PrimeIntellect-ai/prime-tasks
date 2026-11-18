#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import struct
import math

data = []
for i in range(10000):
    val = math.sin(i / 10.0) * 5.0
    if i % 50 == 0:
        val += 50.0 # Outlier
    data.append(val)

mean = sum(data) / len(data)
variance = sum((x - mean) ** 2 for x in data) / (len(data) - 1)
sd = math.sqrt(variance)

filtered_data = [x for x in data if (mean - 2 * sd) <= x <= (mean + 2 * sd)]

with open('/home/user/input_data.bin', 'wb') as f:
    for val in data:
        f.write(struct.pack('<d', val))

with open('/tmp/expected_metrics.txt', 'w') as f:
    f.write(f"Mean: {mean:.6f}\n")
    f.write(f"SD: {sd:.6f}\n")
    f.write(f"Count: {len(filtered_data)}\n")
EOF

    python3 /tmp/generate_data.py
    chown user:user /home/user/input_data.bin

    chmod -R 777 /home/user

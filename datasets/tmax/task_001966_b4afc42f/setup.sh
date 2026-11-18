#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    python3 -c '
import struct
import random
random.seed(42)
data = []
# Create a predictable distribution
for i in range(1000):
    data.extend([100] * 50)
    data.extend([200] * 40)
    data.extend([-5] * 30)
    data.extend([999] * 20)
    data.extend([42] * 10)
    # Add random noise
    for _ in range(500):
        data.append(random.randint(-1000, 1000))

random.shuffle(data)
with open("data.bin", "wb") as f:
    f.write(struct.pack("<" + "i"*len(data), *data))
'

    chmod -R 777 /home/user

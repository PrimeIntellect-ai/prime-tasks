#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng g++ ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /app

    # Generate data and audio
    python3 -c "
import random
import os
import subprocess

random.seed(42)
xs = []
ys = []
for _ in range(50):
    x = round(random.uniform(0, 10), 2)
    y = round(x * 1.5 + random.uniform(-2, 2), 2)
    xs.append(x)
    ys.append(y)

with open('/home/user/data/features.csv', 'w') as f:
    for x in xs:
        f.write(f'{x}\n')

text = ' '.join([str(y) for y in ys])
subprocess.run(['espeak-ng', '-w', '/app/experiment_targets.wav', text])
"

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

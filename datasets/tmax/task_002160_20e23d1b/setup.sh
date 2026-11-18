#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import math
import os

os.makedirs('/home/user', exist_ok=True)

csv_path = '/home/user/energy_signal.csv'
xs = [i * 0.01 for i in range(1001)]
ys = [x * math.cos(x) + math.sin(x) for x in xs]

with open(csv_path, 'w') as f:
    f.write('x,E\n')
    for x, y in zip(xs, ys):
        f.write(f'{x:.2f},{y:.6f}\n')
"

    chmod -R 777 /home/user

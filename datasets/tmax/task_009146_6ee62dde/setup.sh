#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy scikit-learn

    useradd -m -s /bin/bash user || true

    python3 -c "
import csv
import math

a, b, c = 2, 3, 5

with open('/home/user/reference_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['x', 'y'])
    for i in range(100):
        x = i * 0.1
        y = math.sin(a * x) + b * math.cos(c * x)
        writer.writerow([round(x, 1), round(y, 4)])
"

    chmod -R 777 /home/user

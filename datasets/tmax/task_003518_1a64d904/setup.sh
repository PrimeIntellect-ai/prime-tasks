#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import random

random.seed(123)
with open('/home/user/dataset.csv', 'w') as f:
    for _ in range(50):
        # Generate 10 columns. Make columns 2, 5, and 8 have distinctly higher variance
        row = []
        for c in range(10):
            if c == 2:
                val = random.uniform(0, 100)
            elif c == 5:
                val = random.uniform(-50, 50)
            elif c == 8:
                val = random.uniform(200, 300)
            else:
                val = random.uniform(0, 5)
            row.append(f"{val:.4f}")
        f.write(",".join(row) + "\n")
EOF
    python3 /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

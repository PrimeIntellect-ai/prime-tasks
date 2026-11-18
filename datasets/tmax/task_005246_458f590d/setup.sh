#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_dataset.py
import random
import os

os.makedirs('/home/user', exist_ok=True)

random.seed(42)
with open('/home/user/dataset.csv', 'w') as f:
    f.write("id,f1,f2,label\n")
    for i in range(100):
        f1 = round(random.uniform(0, 100), 2)
        f2 = round(random.uniform(0, 100), 2)
        label = random.choice([0, 1])
        f.write(f"{i},{f1},{f2},{label}\n")
EOF

python3 /tmp/generate_dataset.py
rm /tmp/generate_dataset.py

chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import random

os.makedirs('/home/user', exist_ok=True)
random.seed(42)

with open('/home/user/data.csv', 'w') as f:
    f.write('id,feature1,age,income,target\n')
    for i in range(1, 1001):
        # 10% missing age
        age = random.randint(20, 80) if random.random() > 0.1 else ''
        income = random.randint(20000, 150000)
        target = random.choice([0, 1])
        f.write(f'{i},X,{age},{income},{target}\n')
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user

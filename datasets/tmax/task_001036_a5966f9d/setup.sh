#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy networkx

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import random

os.makedirs('/home/user', exist_ok=True)

# Generate synthetic 2D material nodes
random.seed(101)
nodes = []
for i in range(1000):
    x = random.uniform(0, 50)
    y = random.uniform(0, 50)
    nodes.append((i, x, y))

with open('/home/user/nodes.csv', 'w') as f:
    f.write('id,x,y\n')
    for n in nodes:
        f.write(f'{n[0]},{n[1]:.4f},{n[2]:.4f}\n')

# Generate synthetic defect centers
defects = []
for i in range(20):
    x = random.uniform(5, 45)
    y = random.uniform(5, 45)
    defects.append((i, x, y))

with open('/home/user/defects.csv', 'w') as f:
    f.write('defect_id,x,y\n')
    for d in defects:
        f.write(f'{d[0]},{d[1]:.4f},{d[2]:.4f}\n')
"

    chmod -R 777 /home/user

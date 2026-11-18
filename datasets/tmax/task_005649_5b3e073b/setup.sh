#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np

os.makedirs('/home/user', exist_ok=True)
np.random.seed(123)

large_cells = np.random.uniform(0.1, 1.5, 500)
tiny_cells = np.random.uniform(0.0001, 0.0499, 5000)

all_cells = np.concatenate([large_cells, tiny_cells])
np.random.shuffle(all_cells)

with open('/home/user/mesh_data.csv', 'w') as f:
    f.write("domain_id,cell_volume\n")
    for i, vol in enumerate(all_cells):
        f.write(f"{i%10},{vol:.10f}\n")
EOF

    python3 /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

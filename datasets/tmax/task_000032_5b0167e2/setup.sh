#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openmpi-bin libopenmpi-dev gcc python3-dev
    pip3 install pytest mpi4py numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/create_data.py
import numpy as np
np.random.seed(42)
true_lambda = 7.3
data = np.random.poisson(true_lambda, 100)
with open('/home/user/data.txt', 'w') as f:
    for x in data:
        f.write(f"{x}\n")
EOF
    python3 /tmp/create_data.py

    chmod -R 777 /home/user

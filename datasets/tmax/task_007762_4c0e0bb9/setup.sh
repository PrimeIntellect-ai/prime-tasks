#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    python3 -c "
import numpy as np

np.random.seed(42)
ref = np.random.normal(5.0, 1.0, 10000)
opt = np.random.normal(5.05, 1.05, 10000)

with open('/home/user/reference.txt', 'w') as f:
    for val in ref:
        f.write(f'{val}\n')

with open('/home/user/optimized.txt', 'w') as f:
    for val in opt:
        f.write(f'{val}\n')
"

    chmod -R 777 /home/user

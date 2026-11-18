#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    python3 -c "
import numpy as np

np.random.seed(123)
data = np.random.normal(loc=10.0, scale=2.5, size=1000)

with open('/home/user/raw_data.txt', 'w') as f:
    for val in data:
        f.write(f'{val:.6f}\n')
"

    chmod -R 777 /home/user

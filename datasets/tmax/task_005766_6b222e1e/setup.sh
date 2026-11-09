#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    # Generate the initial raw_noise.csv file
    python3 -c "
import numpy as np
import os

np.random.seed(42)
noise = np.random.randn(1000, 3)
os.makedirs('/home/user', exist_ok=True)
np.savetxt('/home/user/raw_noise.csv', noise, delimiter=',', fmt='%.6f')
"

    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    python3 -c "
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
v1 = np.random.lognormal(mean=3.0, sigma=0.5, size=2000)
v2 = np.random.lognormal(mean=2.8, sigma=0.4, size=2000)

np.savetxt('/home/user/latency_v1.csv', v1, fmt='%.4f')
np.savetxt('/home/user/latency_v2.csv', v2, fmt='%.4f')
"

    chmod -R 777 /home/user

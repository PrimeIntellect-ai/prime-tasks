#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    python3 -c "
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(10)
A = np.random.normal(5.0, 1.5, 1000)
B = np.random.normal(5.5, 1.6, 1000)

np.savetxt('/home/user/samples_A.txt', A)
np.savetxt('/home/user/samples_B.txt', B)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

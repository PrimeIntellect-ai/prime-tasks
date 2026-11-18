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
np.random.seed(100)
t = np.linspace(0, 10, 50)
alpha_true = 5.0
beta_true = 0.5
y = alpha_true * np.exp(-beta_true * t) + np.random.normal(0, 0.2, size=t.shape)
np.savez('/home/user/data.npz', t=t, y=y)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

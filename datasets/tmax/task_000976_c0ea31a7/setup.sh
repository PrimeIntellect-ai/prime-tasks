#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest numpy

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create experiments directory and generate data
    python3 -c '
import os
import numpy as np

os.makedirs("/home/user/experiments", exist_ok=True)
np.random.seed(42)

for name in ["exp_alpha", "exp_beta", "exp_gamma"]:
    data = np.random.randn(10, 3)
    np.savetxt(f"/home/user/experiments/{name}.csv", data, delimiter=",", fmt="%.6f")
'

    # Set permissions
    chmod -R 777 /home/user

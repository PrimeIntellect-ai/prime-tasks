#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest numpy scikit-learn

    mkdir -p /home/user

    python3 -c "
import numpy as np

np.random.seed(10)
ref = np.random.randn(1000, 3)
cand = np.random.randn(500, 3) + 0.1

np.save('/home/user/reference_data.npy', ref)
np.save('/home/user/candidate_data.npy', cand)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

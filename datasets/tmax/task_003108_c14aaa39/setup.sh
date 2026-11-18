#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Generate the initial datasets
    python3 -c '
import numpy as np
import os

os.makedirs("/home/user", exist_ok=True)

np.random.seed(42)
run1 = np.random.rand(100, 50)
run2 = run1 + np.random.normal(0, 0.01, (100, 50))

np.savetxt("/home/user/outputs_run1.csv", run1, delimiter=",")
np.savetxt("/home/user/outputs_run2.csv", run2, delimiter=",")
'

    chmod -R 777 /home/user

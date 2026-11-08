#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy statsmodels

    mkdir -p /home/user

    python3 -c "
import numpy as np
import pandas as pd
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
n_atoms = 100
b_factors = np.random.uniform(10.0, 50.0, n_atoms)

with open('/home/user/protein.pdb', 'w') as f:
    for i in range(n_atoms):
        f.write(f'ATOM  {i+1:4d}  CA  ALA A{i+1:4d}    {0.0:8.3f}{0.0:8.3f}{0.0:8.3f}  1.00{b_factors[i]:6.2f}           C\n')

X = np.random.randn(n_atoms, 20)
X[:, 0] += b_factors * 0.1
X[:, 1] += b_factors * 0.05
X[:, 2] += b_factors * -0.05

pd.DataFrame(X).to_csv('/home/user/signals.csv', index=False, header=False)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

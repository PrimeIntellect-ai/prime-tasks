#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest matplotlib numpy

    mkdir -p /home/user/mlops/output
    mkdir -p /home/user/archive

    cat << 'EOF' > /home/user/mlops/generate_artifact.py
#!/usr/bin/env python3
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
import os

x = np.linspace(0, 10, 100)
y = np.sin(x)

plt.plot(x, y)
plt.title('Experiment Results')

# BUG: Clearing the figure before saving
plt.clf()

os.makedirs('/home/user/mlops/output', exist_ok=True)
plt.savefig('/home/user/mlops/output/result.png')
EOF

    chmod +x /home/user/mlops/generate_artifact.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

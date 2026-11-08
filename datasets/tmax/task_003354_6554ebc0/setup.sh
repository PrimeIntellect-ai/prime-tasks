#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# Generate a plausible empirical distribution
np.random.seed(42)
x = np.arange(1, 101)
# Create a distribution somewhat close to the theoretical one, but slightly perturbed
alpha_true = 4.65
logits = alpha_true * np.sqrt(x)
logits -= np.max(logits)
p_unnorm = np.exp(logits) * (1 + 0.1 * np.random.randn(100))
p_unnorm = np.clip(p_unnorm, 1e-10, None)
p_emp = p_unnorm / np.sum(p_unnorm)

with open('/home/user/empirical.csv', 'w') as f:
    f.write('x,p\n')
    for i in range(100):
        f.write(f'{x[i]},{p_emp[i]:.10e}\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
from scipy.stats import kstest, norm, expon

# Create data
np.random.seed(42)
lengths = np.random.normal(500, 50, 1000).astype(int)

os.makedirs('/home/user', exist_ok=True)
with open('/home/user/seq_lengths.txt', 'w') as f:
    for i in range(10):
        row = lengths[i*100:(i+1)*100]
        f.write(','.join(map(str, row)) + '\n')

# Ground truth calculation
mu, std = norm.fit(lengths)
stat_n, p_n = kstest(lengths, 'norm', args=(mu, std))

loc, scale = expon.fit(lengths)
stat_e, p_e = kstest(lengths, 'expon', args=(loc, scale))

best_dist = 'normal' if p_n > p_e else 'exponential'
best_p = p_n if p_n > p_e else p_e
expected_output = f"{best_dist},{best_p:.4f}\n"

with open('/home/user/expected_best_fit.log', 'w') as f:
    f.write(expected_output)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

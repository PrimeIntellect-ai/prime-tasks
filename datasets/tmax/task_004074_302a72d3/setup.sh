#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    # Create user
    useradd -m -s /bin/bash user || true

    # Create generate_vector.py
    cat << 'EOF' > /home/user/generate_vector.py
#!/usr/bin/env python3
import os, sys
import numpy as np

if os.environ.get('OMP_NUM_THREADS') != '1' or os.environ.get('OPENBLAS_NUM_THREADS') != '1':
    print("Error: Must restrict OpenMP and OpenBLAS to 1 thread for reproducibility.", file=sys.stderr)
    sys.exit(1)

try:
    seed = int(os.environ.get('NP_SEED', 0))
except ValueError:
    seed = 0

if seed == 0:
    print("Error: NP_SEED environment variable must be set to a valid integer.", file=sys.stderr)
    sys.exit(1)

np.random.seed(seed)
vec = np.random.rand(5)
print(",".join(map(str, vec)))
EOF
    chmod +x /home/user/generate_vector.py

    # Create past_experiments.csv
    cat << 'EOF' > /home/user/past_experiments.csv
exp_id,v1,v2,v3,v4,v5
exp_alpha,0.12,0.88,0.34,0.55,0.11
exp_beta,0.26,0.16,0.28,0.46,0.32
exp_gamma,0.99,0.01,0.05,0.05,0.10
exp_delta,0.50,0.50,0.50,0.50,0.50
exp_epsilon,0.80,0.60,0.20,0.10,0.90
EOF

    # Set permissions
    chmod -R 777 /home/user

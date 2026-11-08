#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils gawk sed
    pip3 install pytest numpy pandas

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import numpy as np

np.random.seed(42)
N = 1000
ID = np.arange(1, N + 1)
X = np.random.normal(50, 15, N)
Y = 2.5 * X + np.random.normal(0, 10, N)

with open("dataset.csv", "w") as f:
    f.write("ID,Feature_X,Feature_Y\n")
    for i in range(N):
        f.write(f"{ID[i]},{X[i]:.4f},{Y[i]:.4f}\n")
EOF
    python3 generate_data.py
    rm generate_data.py

    LC_ALL=C tr -dc '\0-\377' < /dev/urandom | head -c 10000 > /home/user/fixed_rand

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

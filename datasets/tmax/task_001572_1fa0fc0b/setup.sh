#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest numpy pandas

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust

    mkdir -p /home/user
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import os

np.random.seed(42)
data = np.random.randn(100, 3)

with open("/home/user/data.csv", "w") as f:
    f.write("x,y,z\n")
    np.savetxt(f, data, delimiter=",", fmt="%.6f")
EOF
    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

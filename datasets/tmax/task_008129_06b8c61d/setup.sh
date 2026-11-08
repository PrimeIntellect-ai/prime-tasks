#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/generate_data.py
with open("/home/user/data/signal.txt", "w") as f:
    for i in range(400):
        obs = i // 100
        bin_idx = i % 100
        val = bin_idx * 0.5 + obs * 2.0
        f.write(f"{val:.1f}\n")
EOF
    python3 /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

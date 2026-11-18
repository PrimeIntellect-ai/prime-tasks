#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_log.py
import math
with open('/home/user/sim_output.log', 'w') as f:
    for i in range(51):
        t = i * 0.1
        val = math.sin(4 * t)
        f.write(f"[INFO] t={t:.1f}\n")
        f.write(f"[DEBUG] calc step {i}\n")
        f.write(f"[DATA] val={val:.4f}\n")
EOF
    python3 /tmp/gen_log.py
    rm /tmp/gen_log.py

    chmod -R 777 /home/user

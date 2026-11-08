#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /tmp/generate_artifacts.py
import struct

baseline_path = '/home/user/artifacts/baseline.bin'
experiment_path = '/home/user/artifacts/experiment.bin'

with open(baseline_path, 'wb') as f_base, open(experiment_path, 'wb') as f_exp:
    for i in range(1000000):
        # Baseline is just i * 0.001
        base_val = i * 0.001
        # Experiment has a repeating error pattern: +0.00, +0.01, +0.02, +0.03, +0.04
        error = (i % 5) * 0.01
        exp_val = base_val + error

        f_base.write(struct.pack('<d', base_val))
        f_exp.write(struct.pack('<d', exp_val))
EOF

    python3 /tmp/generate_artifacts.py
    rm /tmp/generate_artifacts.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

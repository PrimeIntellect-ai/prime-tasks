#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip ffmpeg g++
    pip3 install pytest numpy

    mkdir -p /app/data/clean /app/data/evil /app/hidden_test/clean /app/hidden_test/evil

    # Generate video
    # 0x707070 is RGB(112, 112, 112), which gives an average intensity of ~112
    ffmpeg -f lavfi -i color=c=0x707070:s=320x240:r=30 -frames:v 150 -c:v libx264 -crf 0 /app/experiment_run.mp4

    # Generate CSV files
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import os

def gen_data(path, is_evil, n_files=10):
    for i in range(n_files):
        data = np.random.randn(100, 5)
        if is_evil:
            # Increase variance of columns 3 and 4
            data[:, 3:5] = np.random.randn(100, 2) * 5.0
        np.savetxt(os.path.join(path, f"sample_{i:03d}.csv"), data, delimiter=",")

gen_data("/app/data/clean", False)
gen_data("/app/data/evil", True)
gen_data("/app/hidden_test/clean", False)
gen_data("/app/hidden_test/evil", True)
EOF
    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app

#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup_data.py
import os
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(123)

raw_data = np.random.randn(100000, 10).astype(np.float32)
W_enc = np.random.randn(5, 10).astype(np.float32)
W_dec = np.random.randn(10, 5).astype(np.float32)
bias = np.random.randn(10).astype(np.float32)

raw_data.tofile('/home/user/data/raw_data.bin')
W_enc.tofile('/home/user/data/encoder_weights.bin')
W_dec.tofile('/home/user/data/decoder_weights.bin')
bias.tofile('/home/user/data/bias.bin')
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user

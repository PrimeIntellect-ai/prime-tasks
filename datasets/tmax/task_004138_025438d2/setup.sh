#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import os

np.random.seed(42)
vectors = np.random.randn(100, 64).astype(np.float32)
vectors.tofile('/home/user/embeddings.bin')
EOF
    python3 /tmp/gen_data.py

    chmod -R 777 /home/user

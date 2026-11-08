#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest numpy scipy flask fastapi uvicorn requests

    useradd -m -s /bin/bash user || true

    python3 -c "
import numpy as np
import os
os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)
vectors = np.random.randn(5000, 100).astype(np.float32)
np.save('/home/user/vectors.npy', vectors)
"

    chmod -R 777 /home/user

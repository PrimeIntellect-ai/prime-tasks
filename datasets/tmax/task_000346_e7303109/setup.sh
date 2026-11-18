#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
    pip3 install --default-timeout=100 pytest numpy pillow

    mkdir -p /app/src /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /app/src/rk4_core.c
int dummy_function() {
    return 42;
}
EOF

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
from PIL import Image, ImageDraw

# Create parameters image
img = Image.new('RGB', (800, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), "SYSTEM PARAMS: GAMMA=0.15, OMEGA=3.14, DIVERGENCE_THRESHOLD=100.0", fill=(0,0,0))
img.save('/app/parameters.png')

# Create clean trajectory (Energy <= 100)
# Energy = 0.5 * v^2 + 0.5 * OMEGA^2 * x^2
# OMEGA = 3.14, OMEGA^2 = 9.8596
# x = 2, v = 2 -> Energy = 0.5*4 + 0.5*9.8596*4 = 2 + 19.7192 = 21.7192 <= 100
clean_data = np.zeros((10, 3))
clean_data[:, 0] = np.arange(10) # time
clean_data[:, 1] = 2.0 # position
clean_data[:, 2] = 2.0 # velocity
np.save('/app/corpora/clean/clean_traj.npy', clean_data)

# Create evil trajectory (Energy > 100)
# x = 10, v = 10 -> Energy = 0.5*100 + 0.5*9.8596*100 = 50 + 492.98 = 542.98 > 100
evil_data = np.zeros((10, 3))
evil_data[:, 0] = np.arange(10)
evil_data[:, 1] = 10.0
evil_data[:, 2] = 10.0
np.save('/app/corpora/evil/evil_traj.npy', evil_data)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app

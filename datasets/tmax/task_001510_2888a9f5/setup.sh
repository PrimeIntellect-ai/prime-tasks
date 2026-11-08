#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest numpy

    # Create the user
    useradd -m -s /bin/bash user || true

    # Generate the dataset
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np

# Generate deterministic data
np.random.seed(42)
data = np.random.normal(loc=2.5, scale=1.0, size=10000)

with open("/home/user/measurements.csv", "w") as f:
    for val in data:
        f.write(f"{val:.6f}\n")
EOF
    python3 /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /home/user

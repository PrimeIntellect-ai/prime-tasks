#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np

# Set seed for reproducibility
np.random.seed(42)

# Generate Laplace distributed data
data = np.random.laplace(loc=5.0, scale=2.0, size=500)

# Save to file
np.savetxt("/home/user/data.txt", data)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user

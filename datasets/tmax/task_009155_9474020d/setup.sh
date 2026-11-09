#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scikit-learn scipy

    useradd -m -s /bin/bash user || true

    # Generate the dataset
    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np

# Create dataset
np.random.seed(42)
# True rank is 15
X_base = np.random.randn(1000, 15)
transformation = np.random.randn(15, 50)
X = X_base @ transformation

# Save to CSV
os.makedirs('/home/user', exist_ok=True)
np.savetxt('/home/user/dataset.csv', X, delimiter=',')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user

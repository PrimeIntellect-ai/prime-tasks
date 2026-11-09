#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    # Create the user and home directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Generate the initial state files
    python3 -c "
import os
import json
import csv
import random
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# 1. Create weights.json
np.random.seed(123)
W1 = np.random.randn(3, 4).tolist()
b1 = np.random.randn(4).tolist()
W2 = np.random.randn(4, 1).tolist()
b2 = np.random.randn(1).tolist()

weights = {
    'W1': W1,
    'b1': b1,
    'W2': W2,
    'b2': b2
}

with open('/home/user/weights.json', 'w') as f:
    json.dump(weights, f)

# 2. Create raw_data.csv
random.seed(123)
categories = ['Alpha', 'Beta', 'Gamma']
with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'category', 'f1', 'f2', 'f3'])
    for i in range(1, 151):
        cat = random.choice(categories)
        f1 = round(random.uniform(-2, 2), 4)
        f2 = round(random.uniform(-2, 2), 4)
        f3 = round(random.uniform(-2, 2), 4)

        # Introduce missing values occasionally
        if random.random() < 0.1:
            f1 = ''
        if random.random() < 0.1:
            f2 = ''

        writer.writerow([i, cat, f1, f2, f3])
"

    # Set permissions
    chmod -R 777 /home/user

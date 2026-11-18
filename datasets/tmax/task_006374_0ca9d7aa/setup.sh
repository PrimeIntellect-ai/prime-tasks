#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas matplotlib

    mkdir -p /home/user
    cd /home/user

    # Generate mock data
    cat << 'EOF' > generate_data.py
import random
random.seed(42)
with open('data.csv', 'w') as f:
    for _ in range(100):
        x = random.uniform(0, 10)
        y = 2.5 * x + 1.0 + random.gauss(0, 2)
        f.write(f"{x:.4f},{y:.4f}\n")
EOF
    python3 generate_data.py
    rm generate_data.py

    # Create the buggy inference script
    cat << 'EOF' > inference.py
import sys
import pandas as pd
import matplotlib.pyplot as plt
import json

if len(sys.argv) != 2:
    print("Usage: python inference.py <dataset.csv>")
    sys.exit(1)

# 1. Load data
df = pd.read_csv(sys.argv[1], header=None, names=['X', 'Y'])

# 2. Model reconstruction & inference
df['Y_pred'] = 2.5 * df['X'] + 1.0
mean_error = float((df['Y'] - df['Y_pred']).mean())

# 3. Plotting (BUG: plt.show() clears the figure before savefig)
plt.scatter(df['X'], df['Y'], label='Data')
plt.plot(df['X'], df['Y_pred'], color='red', label='Model')
plt.legend()
plt.show()
plt.savefig('output.png')

# 4. Experiment tracking
with open('metrics.json', 'w') as f:
    json.dump({'mean_error': mean_error}, f)
EOF
    chmod +x inference.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

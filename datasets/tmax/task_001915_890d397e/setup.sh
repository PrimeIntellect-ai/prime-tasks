#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

random.seed(42)
successes = 3450
trials = 10000

data = [1] * successes + [0] * (trials - successes)
random.shuffle(data)

with open('/home/user/data/conversions.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'clicked'])
    for i, val in enumerate(data):
        writer.writerow([i, val])
EOF
    python3 /tmp/generate_data.py

    cat << 'EOF' > /home/user/analyze.py
import pandas as pd
import matplotlib.pyplot as plt
import scipy.stats as stats

# BUG: trying to read a non-existent file path
df = pd.read_csv('conversions_data.csv')

successes = df['clicked'].sum()
trials = len(df)

# Prior
alpha_prior = 1
beta_prior = 1

# Posterior (BUG: wrong formulas)
alpha_post = alpha_prior
beta_post = beta_prior

# BUG: not saving metrics to JSON

# Plotting
x = [i/1000.0 for i in range(1001)]
y = stats.beta.pdf(x, alpha_post, beta_post)
plt.plot(x, y)
plt.show() # BUG: blocks execution in headless, doesn't save
plt.savefig('/home/user/artifacts/posterior.png') # BUG: saves blank after show()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

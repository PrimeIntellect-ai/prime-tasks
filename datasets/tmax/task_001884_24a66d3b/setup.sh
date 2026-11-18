#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest matplotlib

    mkdir -p /home/user/mlops_pipeline
    cd /home/user/mlops_pipeline

    cat << 'EOF' > generate_embeddings.py
import argparse
import random

parser = argparse.ArgumentParser()
parser.add_argument('--batch_size', type=int, required=True)
args = parser.parse_args()

# Mock inference latency
latency = args.batch_size * 12 + 8
print(f"Batch Size: {args.batch_size}")
print(f"Latency: {latency} ms")

# Mock embeddings generation
with open('embeddings.csv', 'w') as f:
    f.write("f1,f2,f3,f4\n")
    for _ in range(args.batch_size * 5):
        f.write(",".join([str(random.random()) for _ in range(4)]) + "\n")
EOF

    cat << 'EOF' > plot_artifacts.py
import matplotlib
# Bad backend for headless env causing issues, and missing savefig
matplotlib.use('TkAgg') 
import matplotlib.pyplot as plt
import csv

data = []
try:
    with open('embeddings.csv', 'r') as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            data.append([float(x) for x in row])
except FileNotFoundError:
    pass

if data:
    plt.plot([x[0] for x in data], [x[1] for x in data], 'ro')
    plt.title("PCA of Embeddings")
    plt.show() # Fails to save to artifact_plot.png
EOF

    chmod +x generate_embeddings.py plot_artifacts.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user

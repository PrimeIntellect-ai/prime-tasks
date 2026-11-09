#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy scikit-learn

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/math_dataset/abstracts

    cat << 'EOF' > /tmp/generate_data.py
import os
import csv
import random
import numpy as np

os.makedirs('/home/user/math_dataset/abstracts', exist_ok=True)
random.seed(42)
np.random.seed(42)

# Generate vocabulary
vocab = ["algebra", "topology", "geometry", "manifold", "theorem", "proof", "lemma", "space", "dimension", "vector", "matrix", "tensor", "graph", "node", "edge", "polynomial", "root", "derivative", "integral", "function", "mapping", "group", "ring", "field", "homology", "cohomology", "category", "functor", "sheaf", "scheme", "variety", "bundle", "connection", "curvature", "metric", "measure", "probability", "distribution", "variable", "stochastic", "process", "martingale", "brownian", "motion", "equation", "differential", "solution", "boundary", "condition", "value", "operator", "spectrum", "eigenvalue", "eigenvector", "hilbert", "banach", "norm", "inner", "product", "orthogonal", "basis", "sequence", "series", "convergence", "limit", "asymptotic", "expansion", "bound", "estimate", "inequality", "optimization", "minimum", "maximum", "convex", "concave", "algorithm", "complexity", "computational", "numerical", "method", "scheme", "iteration", "error", "analysis", "stability", "accuracy", "precision", "model", "simulation", "application", "physics", "mechanics", "fluid", "solid", "quantum", "relativity"]

# Generate abstracts and citations
metadata = []
for i in range(1, 201):
    file_id = f"math_{i:03d}"

    # math_001 and a few others will be clustered together (topology/geometry)
    if i == 1 or i in range(10, 30):
        words = random.choices(vocab[:15], k=50) + random.choices(vocab, k=20)
        citations = int(np.random.normal(50, 15))
    else:
        words = random.choices(vocab, k=70)
        citations = int(np.random.normal(30, 10))

    citations = max(0, citations)

    text = " ".join(words)
    with open(f"/home/user/math_dataset/abstracts/{file_id}.txt", "w") as f:
        f.write(text)

    metadata.append([file_id, citations])

with open("/home/user/math_dataset/metadata.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["file_id", "citations"])
    writer.writerows(metadata)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user

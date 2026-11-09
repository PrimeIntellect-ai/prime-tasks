#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/graph.json
{
  "nodes": {
    "start": "A",
    "A1": "TT",
    "A2": "CC",
    "B1": "GGG",
    "B2": "AAA",
    "end": "T"
  },
  "edges": [
    {"from": "start", "to": "A1", "weight": 2},
    {"from": "start", "to": "A2", "weight": 5},
    {"from": "A1", "to": "B1", "weight": 8},
    {"from": "A1", "to": "B2", "weight": 3},
    {"from": "A2", "to": "B1", "weight": 4},
    {"from": "A2", "to": "B2", "weight": 6},
    {"from": "B1", "to": "end", "weight": 2},
    {"from": "B2", "to": "end", "weight": 5}
  ]
}
EOF

    cat << 'EOF' > /home/user/energy.py
import numpy as np

def compute_energy(w, seq):
    # w: array-like of length 3
    # seq: string
    f1 = seq.count('A') * 20.0
    f2 = seq.count('C') * 20.0
    f3 = seq.count('G') * 20.0

    terms = np.array([w[0]*f1, w[1]*f2, w[2]*f3])

    # Numerically unstable computation:
    lse = np.log(np.sum(np.exp(terms)))

    penalty = (w[0] - 2)**2 + (w[1] - 3)**2 + (w[2] + 1)**2
    return lse + penalty
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
